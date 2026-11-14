class_name ProjectPlugin
extends RefCounted
## Un plugin de editor de un proyecto, como lo devuelve
## `godot-manager --json --dir <proyecto> plugins`.

## Carpeta dentro de addons/ ("mi_plugin", o "autor/mi_plugin").
var id := ""
var name := ""
var description := ""
var author := ""
var version := ""
var script_path := ""
## Carpeta del plugin (absoluta).
var path := ""
## Activo en project.godot.
var enabled := false
## Activo en project.godot pero sin carpeta.
var missing := false
## Lo que le falta (plugin.cfg ilegible, script que no existe…), en el texto del CLI.
var problems: PackedStringArray = []


## El nombre que se muestra: el de plugin.cfg, o la carpeta.
func display_name() -> String:
	return name if not name.is_empty() else id


func has_problems() -> bool:
	return not problems.is_empty()
