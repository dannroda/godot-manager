//go:build windows

package manager

import (
	"errors"
	"os"
	"os/exec"
	"os/signal"
	"strings"
)

// Windows no tiene exec: se lanza el binario como hijo con la misma consola,
// se espera y se sale con su codigo.
func execBinary(bin string, args []string) error {
	cmd := exec.Command(consoleBinary(bin), args...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	// Ctrl+C le llega a todos los procesos de la consola: que lo maneje Godot
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt)
	err := cmd.Run()
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		os.Exit(exitErr.ExitCode())
	}
	if err != nil {
		return err
	}
	os.Exit(0)
	return nil
}

// El Godot.exe oficial es una app GUI: su salida no llega a la terminal. Al
// lado viene un Godot_console.exe que la reenvia; si existe, se usa ese.
func consoleBinary(bin string) string {
	if strings.HasSuffix(strings.ToLower(bin), ".exe") {
		c := bin[:len(bin)-4] + "_console.exe"
		if _, err := os.Stat(c); err == nil {
			return c
		}
	}
	return bin
}
