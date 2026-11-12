// godot: corre la version de Godot que corresponde al directorio actual
// (.godot-version del proyecto, o la default global).
package main

import (
	"os"

	"godot-manager/internal/manager"
)

var version = "dev"

func main() {
	manager.Version = version
	os.Exit(manager.Main(append([]string{"run"}, os.Args[1:]...)))
}
