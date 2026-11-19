package manager

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

// Release con el editor (y el mono) para esta plataforma.
func releaseFor(t *testing.T, tag string, mono bool) release {
	t.Helper()
	r := release{TagName: tag, Prerelease: !strings.HasSuffix(tag, "-stable")}
	for _, m := range []bool{false, true} {
		if m && !mono {
			continue
		}
		names, err := editorAssets(tag, m)
		if err != nil {
			t.Skip(err)
		}
		r.Assets = append(r.Assets, asset{Name: names[0]})
	}
	return r
}

func TestNewerInSeries(t *testing.T) {
	rs := []release{
		releaseFor(t, "4.7.1-stable", true),
		releaseFor(t, "4.7.2-stable", false), // sin mono
		releaseFor(t, "4.7.3-rc1", true),
		releaseFor(t, "4.8-beta3", true),
		releaseFor(t, "4.8-rc1", true),
		releaseFor(t, "4.9-dev1", true),
		{TagName: "4.7.9-stable"}, // sin editor para esta plataforma
	}
	cases := []struct {
		tag  string
		mono bool
		want string
	}{
		{"4.7-stable", false, "4.7.2-stable"},
		{"4.7-stable", true, "4.7.1-stable"},
		{"4.7.2-stable", false, ""},
		{"4.8-beta1", false, "4.8-rc1"},
		{"4.8-rc1", false, ""},
		{"4.6-stable", false, ""},
		{"no-es-un-tag", false, ""},
	}
	for _, c := range cases {
		got := ""
		if r := newerInSeries(rs, c.tag, c.mono); r != nil {
			got = r.TagName
		}
		if got != c.want {
			t.Errorf("newerInSeries(%s, mono=%v) = %q, quiero %q", c.tag, c.mono, got, c.want)
		}
	}
}

// GODOT_DIR y carpeta de templates de prueba, con versiones falsas.
func fakeInstall(t *testing.T, versions ...string) {
	t.Helper()
	pv, pg, pt := versionsDir, godotDir, templatesBase
	t.Cleanup(func() { versionsDir, godotDir, templatesBase = pv, pg, pt })
	godotDir = t.TempDir()
	versionsDir = filepath.Join(godotDir, "versions")
	templatesBase = t.TempDir()
	for _, v := range versions {
		os.MkdirAll(filepath.Join(versionsDir, v), 0o755)
		os.WriteFile(filepath.Join(versionsDir, v, "godot"), []byte("#!/bin/sh\n"), 0o755)
	}
}

func TestPrune(t *testing.T) {
	fakeInstall(t, "4.3-stable", "4.5-stable", "4.8-beta3", "4.8-beta3-mono", "mio")
	os.WriteFile(filepath.Join(versionsDir, "mio", customMarker), nil, 0o644)
	os.WriteFile(filepath.Join(godotDir, "default"), []byte("4.5-stable\n"), 0o644)
	tpl := filepath.Join(templatesBase, "4.3.stable")
	os.MkdirAll(tpl, 0o755)
	os.WriteFile(filepath.Join(tpl, "web_debug.zip"), []byte("12345"), 0o644)

	// un proyecto con .godot-version en una carpeta de arriba
	proj := t.TempDir()
	os.WriteFile(filepath.Join(proj, ".godot-version"), []byte("4.8-beta3\n"), 0o644)
	sub := filepath.Join(proj, "juego")
	os.Mkdir(sub, 0o755)
	// ni la lista del Project Manager ni la carpeta actual de los tests
	t.Setenv("XDG_DATA_HOME", t.TempDir())
	t.Setenv("APPDATA", t.TempDir())
	t.Setenv("HOME", t.TempDir())
	t.Chdir(t.TempDir())

	capture(t, modeJSON)
	res, err := cmdPrune([]string{"--dry-run", sub})
	if err != nil {
		t.Fatal(err)
	}
	cands := res["versions"].([]pruneCandidate)
	var names []string
	for _, c := range cands {
		names = append(names, c.Version)
	}
	if strings.Join(names, ",") != "4.3-stable,4.8-beta3-mono" {
		t.Fatalf("candidatos: %v", names)
	}
	if cands[0].TemplatesDir != tpl || cands[0].TemplatesSize != 5 || cands[1].TemplatesDir != "" {
		t.Errorf("templates: %+v", cands)
	}

	if _, err := cmdPrune([]string{sub}); err == nil {
		t.Fatal("sin --yes y sin terminal deberia fallar")
	}
	assumeYes = true
	t.Cleanup(func() { assumeYes = false })
	if _, err := cmdPrune([]string{sub}); err != nil {
		t.Fatal(err)
	}
	for _, v := range []string{"4.3-stable", "4.8-beta3-mono"} {
		if exists(filepath.Join(versionsDir, v)) {
			t.Errorf("%s deberia estar borrada", v)
		}
	}
	for _, v := range []string{"4.5-stable", "4.8-beta3", "mio"} {
		if !exists(filepath.Join(versionsDir, v)) {
			t.Errorf("%s no deberia estar borrada", v)
		}
	}
	if exists(tpl) {
		t.Error("los templates de 4.3 deberian estar borrados")
	}
}

func TestGodotProjects(t *testing.T) {
	cfg := filepath.Join(t.TempDir(), "projects.cfg")
	os.WriteFile(cfg, []byte("[C:/juegos/uno]\r\n\r\nfavorite=false\r\n\r\n[/home/u/dos]\nfavorite=true\n"), 0o644)
	got := godotProjects(cfg)
	if len(got) != 2 || got[0] != filepath.FromSlash("C:/juegos/uno") || got[1] != filepath.FromSlash("/home/u/dos") {
		t.Errorf("proyectos: %q", got)
	}
	if godotProjects(filepath.Join(t.TempDir(), "no")) != nil {
		t.Error("sin archivo deberia dar nil")
	}
}

func TestCompletionScripts(t *testing.T) {
	for _, sh := range []string{"bash", "zsh", "fish", "powershell"} {
		var b strings.Builder
		switch sh {
		case "bash":
			b.WriteString(bashCompletion())
		case "zsh":
			b.WriteString(zshCompletion())
		case "fish":
			b.WriteString(fishCompletion())
		case "powershell":
			b.WriteString(powershellCompletion())
		}
		s := b.String()
		for _, c := range []string{"upgrade", "prune", "__versions"} {
			if !strings.Contains(s, c) {
				t.Errorf("%s: falta %s", sh, c)
			}
		}
	}
	if err := cmdCompletion("tcsh"); err == nil {
		t.Error("tcsh deberia fallar")
	}
	// que bash lo acepte (en Windows, el de Git)
	bash, err := exec.LookPath("bash")
	if err != nil || runtime.GOOS == "windows" {
		return
	}
	f := filepath.Join(t.TempDir(), "c.bash")
	os.WriteFile(f, []byte(bashCompletion()), 0o644)
	if b, err := exec.Command(bash, "-n", f).CombinedOutput(); err != nil {
		t.Errorf("bash -n: %v\n%s", err, b)
	}
}
