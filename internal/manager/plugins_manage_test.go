package manager

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"testing"
)

func TestParseKitFlags(t *testing.T) {
	rest, f, err := parseKitFlags([]string{"store:a/b@1.0", "--pin", "--name=x", "--godot", "4.5", "--force"},
		"--pin", "--name", "--godot", "--force")
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(rest, []string{"store:a/b@1.0"}) || !f.pin || !f.force || f.name != "x" || f.godot != "4.5" {
		t.Errorf("rest=%v flags=%+v", rest, f)
	}
	if _, _, err := parseKitFlags([]string{"--pin"}, "--force"); err == nil {
		t.Error("una opción que el subcomando no acepta tiene que fallar")
	}
	if _, _, err := parseKitFlags([]string{"--godot"}, "--godot"); err == nil {
		t.Error("--godot sin valor tiene que fallar")
	}
}

func TestKitErrors(t *testing.T) {
	cases := []struct {
		code    string
		details map[string]any
		want    string // código del cliError
		has     []string
	}{
		{"conflicts", map[string]any{"name": "x", "version": "v2", "conflicts": []any{
			map[string]any{"path": "addons/x/a.gd", "reason": "modified"},
			map[string]any{"path": "addons/x/b.gd", "reason": "owned", "owner": "y"},
		}}, codePluginConflicts, []string{"--force", "addons/x/a.gd (se cambió a mano)", "es de y"}},
		{"no_release", map[string]any{"name": "x", "godot": "4.2", "newest": "v2", "godot_min": "4.6"},
			codeNoRelease, []string{"Godot 4.2", "v2, pide Godot 4.6+"}},
		{"incompatible", map[string]any{"name": "x", "version": "v2", "godot": "4.5", "godot_min": "4.6", "godot_max": "4.7"},
			codeIncompatible, []string{"Godot 4.6 a 4.7", "Godot 4.5"}},
		{"rate_limited", map[string]any{"source": "github:a/b"}, codeRateLimited, []string{"github:a/b", "GITHUB_TOKEN"}},
		{"algo_nuevo", nil, codeInternal, []string{"algo_nuevo"}},
	}
	for _, c := range cases {
		err := kitError(c.code, c.details)
		code, details := errorInfo(err)
		if code != c.want || details["reason"] != c.code {
			t.Errorf("%s: código %s (reason %v), se esperaba %s", c.code, code, details["reason"], c.want)
		}
		for _, s := range c.has {
			if !strings.Contains(err.Error(), s) {
				t.Errorf("%s: %q no dice %q", c.code, err.Error(), s)
			}
		}
	}
}

func TestProjectGodot(t *testing.T) {
	proj := t.TempDir()
	writeFiles(t, proj, map[string]string{
		"project.godot": "config_version=5\n\n[application]\n\nconfig/features=PackedStringArray(\"4.5\", \"Forward Plus\")\n",
	})
	if got := projectGodot(proj); got != "4.5" {
		t.Errorf("de config/features: %q", got)
	}
	writeFiles(t, proj, map[string]string{".godot-version": "4.5.1-stable\n"})
	if got := projectGodot(proj); got != "4.5.1-stable" {
		t.Errorf(".godot-version manda: %q", got)
	}
}

func TestManagedPlugins(t *testing.T) {
	proj := pluginProject(t)
	writeFiles(t, proj, map[string]string{
		"plugins.json": `{"plugins": {"good": {"source": "store:ana/good", "version": "v1.2"}, "later": {"source": "github:a/later"}, "sprites": {"source": "store:ana/sprites"}, "gone": {"source": "store:ana/gone"}}}`,
		"plugins.lock": `{"schema": 1, "plugins": {"good": {"source": "store:ana/good", "version": "v1.2", "folders": ["addons/good"], "files": {}},
			"sprites": {"source": "store:ana/sprites", "version": "1.0", "folders": ["addons/sprites", "assets/sprites"], "files": {}},
			"gone": {"source": "store:ana/gone", "version": "1.0", "folders": ["addons/gone"], "files": {}},
			"loops": {"source": "store:ana/loops", "version": "2.0", "folders": [], "files": {"Loops/a.wav": "h", "LICENCE.pdf": "h"}}}}`,
		"addons/sprites/hero.png.txt": "x",
		"Loops/a.wav":                 "x",
	})
	ps, err := projectPlugins(proj)
	if err != nil {
		t.Fatal(err)
	}
	i := slices.IndexFunc(ps, func(p plugin) bool { return p.ID == "good" })
	if i < 0 || ps[i].Managed == nil || ps[i].Managed.Name != "good" || !ps[i].Managed.Pinned {
		t.Fatalf("good tendría que figurar como instalado por plugins add y fijado: %+v", ps[i].Managed)
	}
	if j := slices.IndexFunc(ps, func(p plugin) bool { return p.ID == "broken" }); ps[j].Managed != nil {
		t.Error("broken se instaló a mano")
	}
	pending := pendingPlugins(proj, ps)
	names := []string{}
	for _, m := range pending {
		names = append(names, m.Name)
	}
	if !slices.Equal(names, []string{"gone", "later"}) {
		t.Errorf("pendientes: sin instalar (later) y sin carpeta (gone), no el de recursos: %+v", pending)
	}
	assets := installedAssets(proj, ps)
	if len(assets) != 2 || assets[1].Name != "sprites" || assets[1].Version != "1.0" ||
		!slices.Equal(assets[1].Folders, []string{"addons/sprites", "assets/sprites"}) || assets[1].Pinned {
		t.Errorf("recursos: instalado sin plugin.cfg: %+v", assets)
	}
	if len(assets) > 0 && (assets[0].Name != "loops" || !slices.Equal(assets[0].Folders, []string{"LICENCE.pdf", "Loops"})) {
		t.Errorf("uno de antes sin carpetas en el lock: por sus archivos: %+v", assets[0])
	}
}

func TestKitDir(t *testing.T) {
	pg := godotDir
	t.Cleanup(func() { godotDir = pg })
	godotDir = t.TempDir()
	old := filepath.Join(godotDir, "pluginkit", "viejo")
	writeFiles(t, old, map[string]string{"cli.gd": ""})
	dir, err := kitDir()
	if err != nil {
		t.Fatal(err)
	}
	for _, f := range []string{"cli.gd", "kit.gd", "project.godot"} {
		if !exists(filepath.Join(dir, f)) {
			t.Errorf("falta %s en %s", f, dir)
		}
	}
	if exists(filepath.Join(dir, tempPID)) {
		t.Error("quedó el .pid del temporal")
	}
	if exists(old) {
		t.Error("no borró la versión anterior de la librería")
	}
	again, err := kitDir()
	if err != nil || again != dir {
		t.Errorf("la segunda vez tiene que usar la misma carpeta: %s, %v", again, err)
	}
}

func TestKitGodot(t *testing.T) {
	pv, pg := versionsDir, godotDir
	t.Cleanup(func() { versionsDir, godotDir = pv, pg })
	godotDir = t.TempDir()
	versionsDir = filepath.Join(godotDir, "versions")
	exe := "godot"
	if runtime.GOOS == "windows" {
		exe = "godot.exe"
	}
	for _, v := range []string{"4.1.4-stable", "4.3-stable", "4.4-stable", "mio"} {
		p := filepath.Join(versionsDir, v, exe)
		writeFiles(t, filepath.Dir(p), map[string]string{exe: ""})
		os.Chmod(p, 0o755)
	}
	if _, err := kitGodot(); err != nil {
		t.Fatal(err)
	}
	os.WriteFile(filepath.Join(godotDir, "default"), []byte("4.1.4-stable\n"), 0o644)
	bin, _ := kitGodot()
	if !strings.Contains(bin, "4.4-stable") {
		t.Errorf("con la default vieja, la más nueva que sirve: %s", bin)
	}
	os.WriteFile(filepath.Join(godotDir, "default"), []byte("4.3-stable\n"), 0o644)
	if bin, _ := kitGodot(); !strings.Contains(bin, "4.3-stable") {
		t.Errorf("la default si sirve: %s", bin)
	}
	for _, v := range []string{"4.3-stable", "4.4-stable"} {
		os.RemoveAll(filepath.Join(versionsDir, v))
	}
	if _, err := kitGodot(); err == nil {
		t.Error("sin un Godot 4.2+ tiene que fallar")
	}
}

// Un proyecto sin plugins: listas vacías en el JSON, no null (la UI exige 'plugins').
func TestPluginsJSONEmptyLists(t *testing.T) {
	proj := t.TempDir()
	writeFiles(t, proj, map[string]string{"project.godot": "config_version=5\n"})
	ps, err := projectPlugins(proj)
	if err != nil {
		t.Fatal(err)
	}
	data, _ := json.Marshal(pluginList{Project: proj, Plugins: ps, Pending: pendingPlugins(proj, ps), Assets: installedAssets(proj, ps)})
	if s := string(data); !strings.Contains(s, `"plugins":[]`) || !strings.Contains(s, `"pending":[]`) || !strings.Contains(s, `"assets":[]`) {
		t.Errorf("JSON: %s", s)
	}
}
