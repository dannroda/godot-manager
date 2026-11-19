package manager

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

// Un GODOT_DIR de prueba con estas versiones instaladas (binarios vacíos).
func fakeVersions(t *testing.T, names ...string) {
	t.Helper()
	pv, pg := versionsDir, godotDir
	t.Cleanup(func() { versionsDir, godotDir = pv, pg })
	godotDir = t.TempDir()
	versionsDir = filepath.Join(godotDir, "versions")
	exe := "godot"
	if runtime.GOOS == "windows" {
		exe = "godot.exe"
	}
	for _, v := range names {
		writeFiles(t, filepath.Join(versionsDir, v), map[string]string{exe: ""})
		os.Chmod(filepath.Join(versionsDir, v, exe), 0o755)
	}
}

func TestNewProject(t *testing.T) {
	fakeVersions(t, "4.5.1-stable", "3.6-stable")
	dir := filepath.Join(t.TempDir(), "mi juego")
	res, err := cmdNew([]string{dir, "--version", "4.5.1-stable", "--renderer=mobile", "--name", `Mi "juego"`})
	if err != nil {
		t.Fatal(err)
	}
	if res["path"] != dir {
		t.Errorf("path: %v", res["path"])
	}
	pg := readFile(t, filepath.Join(dir, "project.godot"))
	for _, want := range []string{"config_version=5", `config/name="Mi \"juego\""`,
		`config/features=PackedStringArray("4.5", "Mobile")`, `renderer/rendering_method="mobile"`} {
		if !strings.Contains(pg, want) {
			t.Errorf("project.godot no tiene %s:\n%s", want, pg)
		}
	}
	if got := strings.TrimSpace(readFile(t, filepath.Join(dir, ".godot-version"))); got != "4.5.1-stable" {
		t.Errorf(".godot-version: %q", got)
	}
	if !strings.Contains(readFile(t, filepath.Join(dir, ".gitignore")), ".godot/") {
		t.Error(".gitignore sin .godot/")
	}
	if _, err := cmdNew([]string{dir}); err == nil {
		t.Error("una carpeta con archivos tiene que fallar")
	}
	if _, err := cmdNew([]string{filepath.Join(t.TempDir(), "x"), "--version", "3.6-stable"}); err == nil {
		t.Error("Godot 3 tiene que fallar")
	}
	if _, err := cmdNew([]string{filepath.Join(t.TempDir(), "x"), "--renderer", "vulkan"}); err == nil {
		t.Error("renderer desconocido tiene que fallar")
	}
	if _, err := cmdNew([]string{filepath.Join(t.TempDir(), "x"), "--preset", "nada"}); err == nil {
		t.Error("un preset que no existe tiene que fallar antes de crear nada")
	}

	// Sin --version: la default para config/features, sin .godot-version.
	os.WriteFile(filepath.Join(godotDir, "default"), []byte("4.5.1-stable\n"), 0o644)
	other := filepath.Join(t.TempDir(), "otro")
	if _, err := cmdNew([]string{other}); err != nil {
		t.Fatal(err)
	}
	if exists(filepath.Join(other, ".godot-version")) {
		t.Error("sin --version no se fija la versión")
	}
	if pg := readFile(t, filepath.Join(other, "project.godot")); !strings.Contains(pg, `PackedStringArray("4.5", "Forward Plus")`) || strings.Contains(pg, "[rendering]") {
		t.Errorf("project.godot con la default:\n%s", pg)
	}
}

func TestPresets(t *testing.T) {
	fakeVersions(t)
	proj := t.TempDir()
	writeFiles(t, proj, map[string]string{
		"project.godot": "config_version=5\n",
		"plugins.json":  `{"plugins": {"a": {"source": "store:x/a"}, "b": {"source": "github:x/b", "prerelease": true}}}`,
		"plugins.lock":  `{"schema": 1, "plugins": {"a": {"source": "store:x/a", "version": "v1.2.0"}}}`,
	})
	wd, _ := os.Getwd()
	t.Cleanup(func() { os.Chdir(wd) })
	os.Chdir(proj)
	if _, err := cmdPresets([]string{"save", "base", "--pin"}); err != nil {
		t.Fatal(err)
	}
	if _, err := cmdPresets([]string{"save", "base"}); err == nil {
		t.Error("guardar encima sin --force tiene que fallar")
	}
	path, err := findPreset("base")
	if err != nil {
		t.Fatal(err)
	}
	p, err := loadPreset(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(p.Plugins) != 2 || p.Plugins[0].Version != "v1.2.0" || p.Plugins[1].Version != "" || !p.Plugins[1].Prerelease {
		t.Errorf("--pin fija lo instalado, y b (sin instalar) queda libre: %+v", p.Plugins)
	}
	if _, err := cmdPresets([]string{"drop", "base", "a"}); err != nil {
		t.Fatal(err)
	}
	if p, _ := loadPreset(path); len(p.Plugins) != 1 || p.Plugins[0].Name != "b" {
		t.Errorf("después de drop: %+v", p.Plugins)
	}
	if _, err := cmdPresets([]string{"drop", "base", "zzz"}); err == nil {
		t.Error("drop de algo que no está tiene que fallar")
	}
	if list := listPresets(); len(list) != 1 || list[0].Name != "base" {
		t.Errorf("list: %+v", list)
	}
	if _, err := cmdPresets([]string{"remove", "base"}); err != nil || exists(path) {
		t.Errorf("remove: %v", err)
	}
	if _, err := presetPath("../x"); err == nil {
		t.Error("nombre con / tiene que fallar")
	}
}
