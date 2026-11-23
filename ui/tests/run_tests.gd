extends SceneTree
## Corre los tests de `res://tests/` (archivos `test_*.gd`, funciones `test_*`).
##
##   godot --headless --path . --script res://tests/run_tests.gd [-- <filtro>]
##
## El filtro opcional se compara con "archivo:función" (contiene). Sale con
## código 1 si algún test falla. Los de integración necesitan GM_BIN (ruta a
## godot-manager); sin esa variable se saltean.

const TESTS_DIR := "res://tests"

var _passed := 0
var _failed := 0
var _skipped := 0
var _script_errors := ScriptErrors.new()


## Junta los errores de script (los "SCRIPT ERROR" de la consola: un script que
## no compila, una llamada inválida…). Un test que los produce falla aunque sus
## asserts pasen: si no, un script roto quedaba en verde.
class ScriptErrors extends Logger:
	var _mutex := Mutex.new()
	var _errors: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mutex.lock()
		_errors.append("%s (%s:%d, %s)" % [rationale if not rationale.is_empty() else code, file, line, function])
		_mutex.unlock()

	func take() -> PackedStringArray:
		_mutex.lock()
		var out := _errors
		_errors = PackedStringArray()
		_mutex.unlock()
		return out


func _initialize() -> void:
	# Los tests comparan los textos fuente (en español), sea cual sea el idioma
	# del sistema.
	TranslationServer.set_locale("es")
	OS.add_logger(_script_errors)
	_run.call_deferred()


func _run() -> void:
	var filter := ""
	var user_args := OS.get_cmdline_user_args()
	if not user_args.is_empty():
		filter = user_args[0]

	var started := Time.get_ticks_msec()
	for path in _find_test_files(TESTS_DIR):
		await _run_file(path, filter)

	var line := "%d bien, %d mal, %d salteados (%.1f s)" % [
		_passed, _failed, _skipped, (Time.get_ticks_msec() - started) / 1000.0]
	print("\n" + ("FALLÓ: " if _failed > 0 else "OK: ") + line)
	OS.remove_logger(_script_errors)
	quit(1 if _failed > 0 else 0)


func _run_file(path: String, filter: String) -> void:
	_script_errors.take()
	var script := load(path) as GDScript
	var load_errors := _script_errors.take()
	if script == null or not script.can_instantiate() or not load_errors.is_empty():
		print("✗ %s: no compila" % path)
		for e in load_errors:
			print("      error de script: " + e)
		_failed += 1
		return
	var tests: PackedStringArray = []
	for method: Dictionary in script.get_script_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_") and not method_name in tests:
			if filter.is_empty() or ("%s:%s" % [path.get_file(), method_name]).contains(filter):
				tests.append(method_name)
	if tests.is_empty():
		return

	var case := script.new() as TestCase
	if case == null:
		print("✗ %s: no extiende TestCase" % path)
		_failed += 1
		return
	case.tree = self
	print("%s" % path.get_file())
	await case.before_all()
	for test_name in tests:
		case._reset()
		_script_errors.take()
		await case.before_each()
		if case._get_skip_reason().is_empty():
			await case.call(test_name)
		await case.after_each()
		_report(test_name, case)
	await case.after_all()


func _report(test_name: String, case: TestCase) -> void:
	var failures := case._get_failures()
	for e in _script_errors.take():
		failures.append("error de script: " + e)
	var skip := case._get_skip_reason()
	if not failures.is_empty():
		_failed += 1
		print("  ✗ %s" % test_name)
		for f in failures:
			print("      %s" % f)
	elif not skip.is_empty():
		_skipped += 1
		print("  - %s (salteado: %s)" % [test_name, skip])
	else:
		_passed += 1
		print("  ✓ %s" % test_name)


static func _find_test_files(dir_path: String) -> PackedStringArray:
	var found: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for sub in dir.get_directories():
		found.append_array(_find_test_files(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd"):
			found.append(dir_path.path_join(file))
	found.sort()
	return found
