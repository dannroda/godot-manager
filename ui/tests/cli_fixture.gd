class_name CliFixture
extends RefCounted
## GODOT_DIR temporal con versiones falsas, para probar contra el CLI real.
##
##   var fx := CliFixture.new()
##   if not fx.available(): skip(fx.why_unavailable()); return
##   fx.setup(["4.2-fake", "4.3-fake"])
##   var r := fx.run(["--json", "list"])   # {exit, stdout}
##   fx.teardown()
##
## Los procesos hijos heredan GODOT_DIR porque se cambia con OS.set_environment;
## teardown la restaura y borra la carpeta.

var gm_bin := ""
var root := ""

var _old_godot_dir := ""
var _had_godot_dir := false


func _init() -> void:
	gm_bin = OS.get_environment("GM_BIN")


func available() -> bool:
	return not gm_bin.is_empty() and FileAccess.file_exists(gm_bin)


func why_unavailable() -> String:
	if gm_bin.is_empty():
		return "falta GM_BIN (ruta a godot-manager)"
	return "GM_BIN no existe: " + gm_bin


## Crea la carpeta y agrega cada versión con `add <nombre> <ejecutable>`.
## Devuelve false (y deja el motivo en `last_error`) si `add` falla.
var last_error := ""


func setup(versions: PackedStringArray = []) -> bool:
	root = OS.get_user_data_dir().path_join("test_godot_dir_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(root)
	_had_godot_dir = OS.has_environment("GODOT_DIR")
	_old_godot_dir = OS.get_environment("GODOT_DIR")
	OS.set_environment("GODOT_DIR", root)
	for v in versions:
		var r := run(["--json", "add", v, fake_executable()])
		if r["exit"] != 0:
			last_error = "add %s: %s" % [v, r["stdout"]]
			return false
	return true


func teardown() -> void:
	if _had_godot_dir:
		OS.set_environment("GODOT_DIR", _old_godot_dir)
	else:
		OS.unset_environment("GODOT_DIR")
	if not root.is_empty() and root.begins_with(OS.get_user_data_dir()):
		_remove_tree(root)
	root = ""


## Corre el CLI bloqueando (solo para tests). stdout y código de salida.
func run(args: PackedStringArray) -> Dictionary:
	var out: Array = []
	var code := OS.execute(gm_bin, args, out, false)
	return {"exit": code, "stdout": "".join(out)}


## Corre el CLI y parsea stdout como JSON (null si no es JSON).
func run_json(args: PackedStringArray) -> Variant:
	return JSON.parse_string(run(args)["stdout"])


## Un ejecutable cualquiera que exista, para que `add` lo copie.
static func fake_executable() -> String:
	if OS.get_name() == "Windows":
		return OS.get_environment("SystemRoot").path_join("System32/whoami.exe")
	return "/bin/true"


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
