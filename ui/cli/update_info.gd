class_name UpdateInfo
extends RefCounted
## Si hay una versión nueva de godot-manager, como lo devuelve
## `godot-manager --json self-update --check`.

var current := ""
var latest := ""
var update_available := false
## Se puede actualizar sola (si no, `reason` dice por qué).
var can_update := false
var reason := ""
## Página de la release (las novedades).
var url := ""
## Carpeta que se actualiza.
var dir := ""
