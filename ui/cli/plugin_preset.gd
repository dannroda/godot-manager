class_name PluginPreset
extends RefCounted
## Un preset de plugins de `presets` (2.4+): los que uno suele usar.

var name := ""
var path := ""
## [{name, source, version}]: version "" = la más nueva que ande.
var plugins: Array[Dictionary] = []


## "dialogue-manager, godot-agent v0.1.32".
func summary() -> String:
	var parts: PackedStringArray = []
	for p in plugins:
		parts.append(p.name + ((" " + p.version) if not str(p.version).is_empty() else ""))
	return ", ".join(parts)
