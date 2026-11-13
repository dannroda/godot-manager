class_name ProjectEntry
extends RefCounted
## Un proyecto de Godot de la lista: lo que dice su project.godot (leído con
## ConfigFile, como hace el Project Manager; no es lógica del CLI).

const PROJECT_FILE := "project.godot"

## Carpeta del proyecto (absoluta, sin barra final).
var path := ""
## `application/config/name`; si no tiene, el nombre de la carpeta.
var name := ""
## `application/config/features` (ej. ["4.8", "GL Compatibility"]).
var features := PackedStringArray()
## Ruta absoluta del ícono, o vacía si no tiene o no se puede resolver.
var icon_path := ""
## Fecha de modificación de project.godot (Unix), para ordenar.
var modified := 0
## La carpeta o su project.godot ya no existen.
var missing := false
## project.godot existe pero no se pudo leer.
var unreadable := false
var _config_version := 0


## Versión de Godot con que se creó o se guardó por última vez ("4.8"); para
## proyectos de Godot 3 (sin features) "3.x"; vacía si no se sabe.
func created_with() -> String:
	for f in features:
		if f.length() > 0 and f[0].is_valid_int() and f.contains("."):
			return f
	if _config_version == 4:
		return "3.x"
	return ""


## Lee el proyecto de la carpeta `dir`. Nunca falla: si falta o no se puede
## leer, queda marcado y con el nombre de la carpeta.
static func read(dir: String) -> ProjectEntry:
	var e := ProjectEntry.new()
	e.path = normalize(dir)
	e.name = e.path.get_file()
	var file := e.path.path_join(PROJECT_FILE)
	if not FileAccess.file_exists(file):
		e.missing = true
		return e
	e.modified = FileAccess.get_modified_time(file)
	var cfg := ConfigFile.new()
	if cfg.load(file) != OK:
		e.unreadable = true
		return e
	e._config_version = int(cfg.get_value("", "config_version", 0))
	var n := str(cfg.get_value("application", "config/name", "")).strip_edges()
	if not n.is_empty():
		e.name = n
	var feats: Variant = cfg.get_value("application", "config/features", PackedStringArray())
	if feats is PackedStringArray:
		e.features = feats
	e.icon_path = resolve_res(e.path, str(cfg.get_value("application", "config/icon", "")))
	return e


## `res://icon.svg` → `<proyecto>/icon.svg`. Los `uid://` no se resuelven
## (haría falta el caché del editor del proyecto): sin ícono.
static func resolve_res(project_dir: String, res_path: String) -> String:
	if not res_path.begins_with("res://"):
		return ""
	var rel := res_path.trim_prefix("res://")
	if rel.is_empty() or rel.contains(".."):
		return ""
	return project_dir.path_join(rel)


## Ruta comparable: absoluta, con `/`, sin barra final (salvo la raíz) y con
## la letra de unidad de Windows en mayúscula (`c:\x` y `C:/x` son la misma).
static func normalize(dir: String) -> String:
	var p := dir.strip_edges().replace("\\", "/").simplify_path()
	while p.length() > 1 and p.ends_with("/") and not p.ends_with(":/"):
		p = p.left(-1)
	if p.length() >= 2 and p[1] == ":" and p[0].to_lower() != p[0].to_upper():
		p = p[0].to_upper() + p.substr(1)
	return p
