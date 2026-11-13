class_name RemoteVersion
extends RefCounted
## Un release oficial, como lo devuelve `godot-manager --json list-remote`.
## Los bools y tamaños son para la plataforma donde corre el CLI.

var tag := ""
var prerelease := false
## Fecha ISO 8601 de GitHub ("2026-11-09T16:16:14Z").
var published_at := ""
var editor := true
var mono := false
var debug_symbols := false
var templates := false
var mono_templates := false
var editor_size := 0
var mono_size := 0
var templates_size := 0
## Página de la release en GitHub (CLI 2.2+; vacía con uno anterior).
var url := ""


## Una release de la que solo se sabe el tag (por ejemplo, la que fija un
## proyecto): todo habilitado, decide el CLI.
static func unknown(p_tag: String) -> RemoteVersion:
	var r := RemoteVersion.new()
	r.tag = p_tag
	r.mono = true
	r.debug_symbols = true
	r.templates = true
	r.mono_templates = true
	return r


## "4.8-beta3" → [4, 8, 0]; sirve para ordenar por versión.
func version_numbers() -> PackedInt32Array:
	return GmParse.version_numbers(tag)
