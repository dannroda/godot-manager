//go:build windows

package manager

import (
	"errors"
	"os"
	"os/exec"
	"os/signal"
	"strings"
	"syscall"
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

const (
	detachedProcess                = 0x00000008
	processQueryLimitedInformation = 0x1000
	stillActive                    = 259
)

// Lanza el binario GUI (sin el _console.exe, asi no abre una consola) como
// proceso independiente y vuelve enseguida.
func startDetached(bin string, args []string) (int, error) {
	cmd := exec.Command(bin, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{
		CreationFlags: detachedProcess | syscall.CREATE_NEW_PROCESS_GROUP,
	}
	if err := cmd.Start(); err != nil {
		return 0, err
	}
	pid := cmd.Process.Pid
	cmd.Process.Release()
	return pid, nil
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

func processAlive(pid int) bool {
	h, err := syscall.OpenProcess(processQueryLimitedInformation, false, uint32(pid))
	if err != nil {
		// existe pero es de otro usuario
		return errors.Is(err, syscall.ERROR_ACCESS_DENIED)
	}
	defer syscall.CloseHandle(h)
	var code uint32
	if err := syscall.GetExitCodeProcess(h, &code); err != nil {
		return false
	}
	return code == stillActive
}
