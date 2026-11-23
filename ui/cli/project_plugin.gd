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
## Lo instaló `plugins add` (está en plugins.lock): su nombre ahí, de dónde viene
## ("store:pub/slug", "github:owner/repo") y la versión instalada.
var managed_name := ""
var source := ""
var locked_version := ""
## Fijado en plugins.json: update no lo toca.
var pinned := false
## Está en plugins.json pero no instalado (no tiene carpeta ni datos de plugin.cfg).
var pending := false
## Lo instaló `plugins add` pero no trae plugin.cfg: recursos (arte, sonido,
## scripts). No se activa; se actualiza y se desinstala como un plugin.
var asset := false
## Las carpetas que instaló (relativas al proyecto); solo las de `asset`.
var folders: PackedStringArray = []


## El nombre que se muestra: el de plugin.cfg, o la carpeta.
func display_name() -> String:
	return name if not name.is_empty() else id


func is_managed() -> bool:
	return not managed_name.is_empty()


func has_problems() -> bool:
	return not problems.is_empty()
