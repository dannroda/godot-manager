class_name PathStatus
extends RefCounted
## Si godot-manager está en el PATH, como lo devuelve `godot-manager --json path`.

## Carpeta de godot-manager.
var dir := ""
## Si una terminal nueva lo encuentra.
var on_path := false
## Qué toca `path add`: el PATH del usuario (Windows) o ~/.local/bin.
var target := ""
## Quién lo instaló si fue un gestor de paquetes (el PATH lo maneja él), o "".
var managed := ""
