// godot-manager: instala y selecciona versiones de Godot.
package main

import (
	"os"

	"godot-manager/internal/manager"
)

var version = "dev"

func main() {
	manager.Version = version
	os.Exit(manager.Main(os.Args[1:]))
}
