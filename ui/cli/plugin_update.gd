class_name PluginUpdate
extends RefCounted
## Un plugin de plugins.lock según `plugins outdated` (2.4+).

var name := ""
var source := ""
## La instalada.
var version := ""
## La más nueva que anda con el Godot del proyecto ("" si ninguna).
var latest := ""
## `latest` es más nueva que la instalada.
var newer := false
var pinned := false
## La instalada ya no anda con el Godot del proyecto.
var incompatible := false
## La más nueva que no anda con el Godot del proyecto, si es más nueva que
## `latest` ("" si no hay), y qué Godot pide.
var blocked_version := ""
var blocked_min := ""
var blocked_max := ""


## "Godot 4.6+", "Godot 4.3 a 4.5"…
func blocked_godot() -> String:
	if not blocked_min.is_empty() and not blocked_max.is_empty():
		return TranslationServer.translate("Godot %s a %s") % [blocked_min, blocked_max]
	if not blocked_min.is_empty():
		return "Godot %s+" % blocked_min
	if not blocked_max.is_empty():
		return TranslationServer.translate("Godot %s o anterior") % blocked_max
	return TranslationServer.translate("otra versión de Godot")
