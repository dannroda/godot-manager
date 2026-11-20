package manager

import (
	"path/filepath"
	"runtime"
	"testing"
)

func TestSamePath(t *testing.T) {
	a := filepath.Join("x", "godot-manager")
	if !samePath(a, filepath.Join("x", "sub", "..", "godot-manager")) {
		t.Error("no limpia la ruta")
	}
	if samePath(a, filepath.Join("x", "otra")) {
		t.Error("carpetas distintas dan iguales")
	}
	want := runtime.GOOS == "windows" || runtime.GOOS == "darwin"
	if got := samePath(a, filepath.Join("X", "Godot-Manager")); got != want {
		t.Errorf("mayúsculas: %v, se esperaba %v", got, want)
	}
}
