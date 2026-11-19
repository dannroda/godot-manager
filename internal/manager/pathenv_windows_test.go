//go:build windows

package manager

import (
	"os/exec"
	"path/filepath"
	"syscall"
	"testing"
)

// path add/remove contra una clave de prueba, no el PATH real del usuario.
func TestWindowsUserPath(t *testing.T) {
	key := `Software\godot-manager-test`
	if b, err := exec.Command("reg", "add", `HKCU\`+key, "/v", "Path", "/t", "REG_EXPAND_SZ", "/d", `%SystemRoot%;C:\otra`, "/f").CombinedOutput(); err != nil {
		t.Skipf("reg add: %v %s", err, b)
	}
	t.Cleanup(func() { exec.Command("reg", "delete", `HKCU\`+key, "/f").Run() })
	prev := envKey
	envKey = key
	t.Cleanup(func() { envKey = prev })

	exe := filepath.Join(t.TempDir(), "godot-manager.exe")
	if err := addToPath(exe); err != nil {
		t.Fatal(err)
	}
	addToPath(exe) // no la agrega dos veces
	got, typ, err := regGetString(syscall.HKEY_CURRENT_USER, key, "Path")
	if err != nil {
		t.Fatal(err)
	}
	if want := `%SystemRoot%;C:\otra;` + filepath.Dir(exe); got != want || typ != syscall.REG_EXPAND_SZ {
		t.Fatalf("Path = %q (tipo %d), quiero %q", got, typ, want)
	}
	if !pathHas(got, filepath.Dir(exe)+`\`) || !pathHas(got, `C:\Windows`) && !pathHas(got, expandEnv(`%SystemRoot%`)) {
		t.Error("pathHas")
	}
	if err := removeFromPath(exe); err != nil {
		t.Fatal(err)
	}
	if got, _, _ := regGetString(syscall.HKEY_CURRENT_USER, key, "Path"); got != `%SystemRoot%;C:\otra` {
		t.Errorf("despues de remove: %q", got)
	}
}
