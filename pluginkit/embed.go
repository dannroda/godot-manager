// Package pluginkit lleva adentro del binario la librería de plugins (GDScript), para correrla con
// un Godot instalado: ver internal/manager/pluginkit.go.
package pluginkit

import "embed"

//go:embed *.gd project.godot
var Files embed.FS
