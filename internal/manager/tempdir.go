package manager

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// Temporales de install/templates/symbols: .godot-manager.* al lado del
// destino, con un archivo .pid del proceso que los creo. Si el proceso muere
// sin limpiar (la UI cancela con kill, que no deja correr los defer), la
// proxima operacion los borra.
const (
	tempPrefix = ".godot-manager."
	tempPID    = ".pid"
	// temporales de versiones anteriores, sin .pid
	tempMaxAge = 24 * time.Hour
)

func makeTemp(parent string) (string, error) {
	if err := os.MkdirAll(parent, 0o755); err != nil {
		return "", err
	}
	cleanStaleTemps(parent)
	dir, err := os.MkdirTemp(parent, tempPrefix)
	if err != nil {
		return "", err
	}
	if err := os.WriteFile(filepath.Join(dir, tempPID), []byte(strconv.Itoa(os.Getpid())), 0o644); err != nil {
		os.RemoveAll(dir)
		return "", err
	}
	return dir, nil
}

// Borra los temporales de procesos que ya no corren.
func cleanStaleTemps(parent string) {
	ents, _ := os.ReadDir(parent)
	for _, e := range ents {
		if !e.IsDir() || !strings.HasPrefix(e.Name(), tempPrefix) {
			continue
		}
		dir := filepath.Join(parent, e.Name())
		data, err := os.ReadFile(filepath.Join(dir, tempPID))
		if err != nil {
			if fi, err := e.Info(); err == nil && time.Since(fi.ModTime()) > tempMaxAge {
				os.RemoveAll(dir)
			}
			continue
		}
		pid, err := strconv.Atoi(strings.TrimSpace(string(data)))
		if err == nil && pid > 0 && pid != os.Getpid() && processAlive(pid) {
			continue
		}
		os.RemoveAll(dir)
	}
}
