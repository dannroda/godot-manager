class_name DirNaming
extends RefCounted
## El nombre de la carpeta de un proyecto nuevo, como lo arma el Project
## Manager de Godot: el nombre del proyecto con la convención del ajuste
## `project_manager/directory_naming_convention` (kebab-case por defecto) y
## sin los caracteres que no van en una carpeta (OS::get_safe_dir_name).

## Los valores del ajuste, en el orden del editor.
enum Convention { NONE, KEBAB, SNAKE, CAMEL, PASCAL, TITLE }

const SETTING := "project_manager/directory_naming_convention"
const DEFAULT := Convention.KEBAB


static func dir_name(project_name: String, convention: int = DEFAULT) -> String:
	var s := project_name
	match convention:
		Convention.KEBAB:
			s = s.to_kebab_case()
		Convention.SNAKE:
			s = s.to_snake_case()
		Convention.CAMEL:
			s = s.to_camel_case()
		Convention.PASCAL:
			s = s.to_pascal_case()
		Convention.TITLE:
			s = s.capitalize()
	return safe_dir_name(s)


## Igual que OS::get_safe_dir_name de Godot (sin rutas).
static func safe_dir_name(name: String) -> String:
	var s := name.strip_edges()
	if s == ".":
		s = "dot"
	elif s == "..":
		s = "twodots"
	for c in [":", "*", "?", "\"", "<", ">", "|", "/", "\\"]:
		s = s.replace(c, "-")
	while s.ends_with("."):
		s = s.left(-1)
	return s


## La convención que usa el editor: el ajuste del archivo de ajustes de la
## versión más nueva (editor_settings-4.8.tres, …) en `settings_dir`; si no
## hay ninguno o no lo tiene, la default de Godot.
static func read_convention(settings_dir := godot_config_dir()) -> int:
	var best := ""
	var best_version := PackedInt32Array()
	for f in DirAccess.get_files_at(settings_dir):
		if not (f.begins_with("editor_settings-") and f.ends_with(".tres")):
			continue
		var v := _numbers(f.trim_prefix("editor_settings-").trim_suffix(".tres"))
		if best.is_empty() or _newer(v, best_version):
			best = f
			best_version = v
	if best.is_empty():
		return DEFAULT
	var file := FileAccess.open(settings_dir.path_join(best), FileAccess.READ)
	if file == null:
		return DEFAULT
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.begins_with(SETTING + " ") or line.begins_with(SETTING + "="):
			var value := line.get_slice("=", 1).strip_edges()
			if value.is_valid_int() and int(value) >= 0 and int(value) <= Convention.TITLE:
				return int(value)
			return DEFAULT
	return DEFAULT


## La carpeta de configuración del editor de Godot (donde están sus ajustes).
static func godot_config_dir() -> String:
	match OS.get_name():
		"Windows":
			return OS.get_environment("APPDATA").path_join("Godot")
		"macOS":
			return OS.get_environment("HOME").path_join("Library/Application Support/Godot")
	var config := OS.get_environment("XDG_CONFIG_HOME")
	if config.is_empty():
		config = OS.get_environment("HOME").path_join(".config")
	return config.path_join("godot")


static func _numbers(version: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	for part in version.split("."):
		out.append(part.to_int())
	return out


static func _newer(a: PackedInt32Array, b: PackedInt32Array) -> bool:
	for i in maxi(a.size(), b.size()):
		var x := a[i] if i < a.size() else 0
		var y := b[i] if i < b.size() else 0
		if x != y:
			return x > y
	return false
