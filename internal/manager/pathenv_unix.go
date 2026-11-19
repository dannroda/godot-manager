//go:build !windows

package manager

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
)

// ~/.local/bin: esta en el PATH de casi todas las distros (systemd lo pide);
// en macOS hay que agregarlo a mano.
func localBin() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".local", "bin")
}

func pathTarget() string {
	return localBin()
}

// Los ejecutables que van al PATH: godot-manager y el godot de al lado.
func pathExecutables(exe string) []string {
	out := []string{exe}
	if g := filepath.Join(filepath.Dir(exe), "godot"); isExecutable(g) {
		out = append(out, g)
	}
	return out
}

// Si 'godot-manager' en una terminal nueva es este: el PATH actual lo
// encuentra (directo o por un symlink).
func onPath(exe string) bool {
	found, err := exec.LookPath("godot-manager")
	return err == nil && sameFile(found, exe)
}

func addToPath(exe string) error {
	bin := localBin()
	if err := os.MkdirAll(bin, 0o755); err != nil {
		return err
	}
	for _, e := range pathExecutables(exe) {
		link := filepath.Join(bin, filepath.Base(e))
		if fi, err := os.Lstat(link); err == nil {
			if fi.Mode()&os.ModeSymlink == 0 {
				return errf(codeInvalidArgs, "ya hay un %s que no es un symlink: no se toca", link)
			}
			os.Remove(link)
		}
		if err := os.Symlink(e, link); err != nil {
			return err
		}
	}
	return nil
}

// Borra solo los symlinks que apuntan a esta instalacion.
func removeFromPath(exe string) error {
	bin := localBin()
	for _, e := range pathExecutables(exe) {
		link := filepath.Join(bin, filepath.Base(e))
		fi, err := os.Lstat(link)
		if errors.Is(err, os.ErrNotExist) || err == nil && (fi.Mode()&os.ModeSymlink == 0 || !sameFile(link, e)) {
			continue
		}
		if err := os.Remove(link); err != nil {
			return err
		}
	}
	return nil
}
