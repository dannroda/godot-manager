package manager

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeFiles(t *testing.T, root string, files map[string]string) {
	t.Helper()
	for name, body := range files {
		p := filepath.Join(root, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func readFile(t *testing.T, p string) string {
	t.Helper()
	b, err := os.ReadFile(p)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

const project4 = `; Engine configuration file.
config_version=5

[application]

config/name="Demo"

[editor_plugins]

enabled=PackedStringArray("res://addons/good/plugin.cfg", "res://addons/gone/plugin.cfg")

[rendering]

renderer/rendering_method="gl_compatibility"
`

func pluginProject(t *testing.T) string {
	proj := t.TempDir()
	writeFiles(t, proj, map[string]string{
		"project.godot": project4,
		"addons/good/plugin.cfg": `[plugin]

name="Good"
description="Una línea
y otra con \"comillas\""
author="Ana"
version="1.2"
script="plugin.gd"
`,
		"addons/good/plugin.gd":          "@tool\nextends EditorPlugin\n",
		"addons/good/sub/plugin.cfg":     "[plugin]\nname=\"no se lista\"\n",
		"addons/broken/plugin.cfg":       "[plugin]\nname=\"Broken\"\nscript=\"missing.gd\"\n",
		"addons/nested/inner/plugin.cfg": "[plugin]\nname=\"Inner\"\nscript=\"res://addons/nested/inner/p.gd\"\n",
		"addons/nested/inner/p.gd":       "",
		"addons/notaplugin/readme.txt":   "",
	})
	return proj
}

func TestProjectPlugins(t *testing.T) {
	proj := pluginProject(t)
	ps, err := projectPlugins(proj)
	if err != nil {
		t.Fatal(err)
	}
	var ids []string
	byID := map[string]plugin{}
	for _, p := range ps {
		ids = append(ids, p.ID)
		byID[p.ID] = p
	}
	if got := strings.Join(ids, ","); got != "broken,gone,good,nested/inner" {
		t.Fatalf("ids: %s", got)
	}
	g := byID["good"]
	if !g.Enabled || g.Name != "Good" || g.Version != "1.2" || g.Author != "Ana" || len(g.Problems) != 0 {
		t.Errorf("good: %+v", g)
	}
	if g.Description != "Una línea\ny otra con \"comillas\"" {
		t.Errorf("descripcion: %q", g.Description)
	}
	if b := byID["broken"]; b.Enabled || len(b.Problems) != 1 || !strings.Contains(b.Problems[0], "missing.gd") {
		t.Errorf("broken: %+v", b)
	}
	if g := byID["gone"]; !g.Missing || !g.Enabled {
		t.Errorf("gone: %+v", g)
	}
	if n := byID["nested/inner"]; n.Name != "Inner" || len(n.Problems) != 0 {
		t.Errorf("nested: %+v", n)
	}
}

func TestEnableDisablePlugin(t *testing.T) {
	proj := pluginProject(t)
	pg := filepath.Join(proj, "project.godot")

	if _, err := enablePlugin(proj, "good", false); err != nil {
		t.Fatal(err)
	}
	want := strings.Replace(project4, `"res://addons/good/plugin.cfg", `, "", 1)
	if got := readFile(t, pg); got != want {
		t.Fatalf("disable good:\n%s", got)
	}
	res, err := enablePlugin(proj, "nested/inner", true)
	if err != nil || res["changed"] != true {
		t.Fatal(res, err)
	}
	if !strings.Contains(readFile(t, pg), `enabled=PackedStringArray("res://addons/gone/plugin.cfg", "res://addons/nested/inner/plugin.cfg")`) {
		t.Errorf("enable nested:\n%s", readFile(t, pg))
	}
	if res, _ := enablePlugin(proj, "nested/inner", true); res["changed"] != false {
		t.Error("enable dos veces cambio algo")
	}
	if _, err := enablePlugin(proj, "nope", true); err == nil || !strings.Contains(err.Error(), "nope") {
		t.Errorf("plugin inexistente: %v", err)
	}
	if code, _ := errorInfo(func() error { _, err := enablePlugin(proj, "gone", true); return err }()); code != codeNoPlugin {
		t.Errorf("activar uno sin carpeta: %s", code)
	}
	// desactivar el que no tiene carpeta lo saca de la lista
	if _, err := enablePlugin(proj, "gone", false); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(readFile(t, pg), `enabled=PackedStringArray("res://addons/nested/inner/plugin.cfg")`) {
		t.Errorf("disable gone:\n%s", readFile(t, pg))
	}
}

func TestPluginsGodot3AndCRLF(t *testing.T) {
	proj := t.TempDir()
	text := "config_version=4\r\n\r\n[application]\r\n\r\nconfig/name=\"Old\"\r\n\r\n[editor_plugins]\r\n\r\nenabled=PoolStringArray( \"a\", \"b\" )\r\n"
	writeFiles(t, proj, map[string]string{
		"project.godot":       text,
		"addons/a/plugin.cfg": "[plugin]\r\nname=\"A\"\r\nscript=\"a.gd\"\r\n",
		"addons/a/a.gd":       "",
		"addons/b/plugin.cfg": "[plugin]\r\nname=\"B\"\r\nscript=\"b.gd\"\r\n",
		"addons/b/b.gd":       "",
		"addons/c/plugin.cfg": "[plugin]\r\nname=\"C\"\r\nscript=\"c.gd\"\r\n",
		"addons/c/c.gd":       "",
	})
	ps, err := projectPlugins(proj)
	if err != nil {
		t.Fatal(err)
	}
	if len(ps) != 3 || !ps[0].Enabled || !ps[1].Enabled || ps[2].Enabled || ps[0].Name != "A" {
		t.Fatalf("%+v", ps)
	}
	if _, err := enablePlugin(proj, "a", false); err != nil {
		t.Fatal(err)
	}
	if _, err := enablePlugin(proj, "c", true); err != nil {
		t.Fatal(err)
	}
	want := strings.Replace(text, `enabled=PoolStringArray( "a", "b" )`, `enabled=PoolStringArray( "b", "c" )`, 1)
	if got := readFile(t, filepath.Join(proj, "project.godot")); got != want {
		t.Errorf("got %q\nwant %q", got, want)
	}
}

func TestEnableWithoutSection(t *testing.T) {
	proj := t.TempDir()
	writeFiles(t, proj, map[string]string{
		"project.godot":       "config_version=5\n\n[application]\n\nconfig/name=\"X\"\n",
		"addons/p/plugin.cfg": "[plugin]\nname=\"P\"\nscript=\"p.gd\"\n",
		"addons/p/p.gd":       "",
	})
	if _, err := enablePlugin(proj, "p", true); err != nil {
		t.Fatal(err)
	}
	want := "config_version=5\n\n[application]\n\nconfig/name=\"X\"\n\n[editor_plugins]\n\nenabled=PackedStringArray(\"res://addons/p/plugin.cfg\")\n"
	if got := readFile(t, filepath.Join(proj, "project.godot")); got != want {
		t.Errorf("got %q", got)
	}
	if _, err := enablePlugin(proj, "p", false); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(readFile(t, filepath.Join(proj, "project.godot")), "enabled=PackedStringArray()\n") {
		t.Errorf("vacio: %q", readFile(t, filepath.Join(proj, "project.godot")))
	}
}

func TestRemovePlugin(t *testing.T) {
	proj := pluginProject(t)
	defer func(v bool) { assumeYes = v }(assumeYes)
	assumeYes = true
	res, err := removePlugin(proj, "good")
	if err != nil {
		t.Fatal(err)
	}
	if res["removed"] != filepath.Join(proj, "addons", "good") {
		t.Errorf("res: %v", res)
	}
	if _, err := os.Stat(filepath.Join(proj, "addons", "good")); !os.IsNotExist(err) {
		t.Error("la carpeta sigue")
	}
	if strings.Contains(readFile(t, filepath.Join(proj, "project.godot")), "addons/good") {
		t.Error("sigue activo")
	}
	// sin --yes, con --json, pide confirmacion
	assumeYes = false
	defer func(m outMode) { out.mode = m }(out.mode)
	out.mode = modeJSON
	_, err = removePlugin(proj, "broken")
	if code, _ := errorInfo(err); code != codeNeedsConfirmation {
		t.Errorf("sin --yes: %v", err)
	}
}

func TestFindProject(t *testing.T) {
	proj := pluginProject(t)
	wd, _ := os.Getwd()
	defer os.Chdir(wd)
	os.Chdir(filepath.Join(proj, "addons", "good"))
	got, err := findProject()
	if err != nil {
		t.Fatal(err)
	}
	if want, _ := filepath.EvalSymlinks(proj); got != proj && got != want {
		t.Errorf("%s != %s", got, proj)
	}
	os.Chdir(t.TempDir())
	if _, err := findProject(); err == nil {
		t.Error("sin project.godot no fallo")
	}
}
