//go:build !windows

package manager

import (
	"errors"
	"os"
	"os/exec"
	"syscall"
)

// Reemplaza el proceso actual por el binario (no vuelve si sale bien).
func execBinary(bin string, args []string) error {
	return syscall.Exec(bin, append([]string{bin}, args...), os.Environ())
}

// Lanza el binario en su propia sesion, sin terminal, y vuelve enseguida.
func startDetached(bin string, args []string) (int, error) {
	cmd := exec.Command(bin, args...) // stdin/stdout/stderr: /dev/null
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := cmd.Start(); err != nil {
		return 0, err
	}
	pid := cmd.Process.Pid
	cmd.Process.Release()
	return pid, nil
}

// Binario para correr Godot desde una consola y leer su salida.
func consoleBinary(bin string) string {
	return bin
}

func processAlive(pid int) bool {
	err := syscall.Kill(pid, 0)
	return err == nil || errors.Is(err, syscall.EPERM)
}
