class_name Resolution
extends RefCounted
## Qué versión usaría `godot` en una carpeta (`godot-manager --json which`).

var path := ""
var version := ""
## "default", o la ruta del .godot-version que la fijó.
var source := ""


func is_from_default() -> bool:
	return source == "default"
