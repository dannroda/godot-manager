//go:build !windows

package manager

import (
	"os"
	"syscall"
)

// Reemplaza el proceso actual por el binario (no vuelve si sale bien).
func execBinary(bin string, args []string) error {
	return syscall.Exec(bin, append([]string{bin}, args...), os.Environ())
}

// Binario para correr Godot desde una consola y leer su salida.
func consoleBinary(bin string) string {
	return bin
}
