class_name InstalledVersion
extends RefCounted
## Una versión instalada, como la devuelve `godot-manager --json list`.

var name := ""
var path := ""
var is_default := false
var mono := false
var debug_symbols := false
## Tag oficial (vacío si es un build propio).
var tag := ""
var custom := false
## Carpeta de export templates, vacía si no tiene.
var templates_dir := ""
var template_platforms: PackedStringArray = []


func has_templates() -> bool:
	return not templates_dir.is_empty()
