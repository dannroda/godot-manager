class_name TestCase
extends RefCounted
## Base de los tests. Cada `func test_*()` de una subclase es un test; puede
## usar `await`. Los asserts registran la falla y siguen (no abortan el test).
## Ganchos opcionales: before_all, after_all, before_each, after_each.

## El SceneTree del runner, para esperar cuadros o agregar nodos.
var tree: SceneTree

var _failures: PackedStringArray = []
var _skip_reason := ""


func before_all() -> void:
	pass


func after_all() -> void:
	pass


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func assert_eq(actual: Variant, expected: Variant, msg := "") -> bool:
	if typeof(actual) == typeof(expected) and actual == expected:
		return true
	if _both_numbers(actual, expected) and actual == expected:
		return true
	fail("esperaba %s, salió %s%s" % [_show(expected), _show(actual), _suffix(msg)])
	return false


func assert_ne(actual: Variant, unexpected: Variant, msg := "") -> bool:
	if typeof(actual) == typeof(unexpected) and actual == unexpected:
		fail("no esperaba %s%s" % [_show(actual), _suffix(msg)])
		return false
	return true


func assert_true(value: bool, msg := "") -> bool:
	if not value:
		fail("esperaba true%s" % _suffix(msg))
	return value


func assert_false(value: bool, msg := "") -> bool:
	if value:
		fail("esperaba false%s" % _suffix(msg))
	return not value


func assert_has(container: Variant, item: Variant, msg := "") -> bool:
	var found := false
	if container is Dictionary:
		found = (container as Dictionary).has(item)
	elif container is Array or container is PackedStringArray:
		found = item in container
	elif container is String:
		found = (container as String).contains(str(item))
	if not found:
		fail("%s no contiene %s%s" % [_show(container), _show(item), _suffix(msg)])
	return found


func fail(msg: String) -> void:
	_failures.append(msg)


## Marca el test como salteado; conviene hacer `return` justo después.
func skip(reason: String) -> void:
	_skip_reason = reason


## Espera `frames` cuadros del árbol (para jobs del CLI y señales).
func wait_frames(frames: int = 1) -> void:
	for i in frames:
		await tree.process_frame


## Espera hasta que `condition` dé true o pasen `timeout` segundos.
func wait_until(condition: Callable, timeout: float = 10.0) -> bool:
	var limit := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > limit:
			fail("se agotó la espera (%.1f s)" % timeout)
			return false
		await tree.process_frame
	return true


# Uso interno del runner.
func _reset() -> void:
	_failures.clear()
	_skip_reason = ""


func _get_failures() -> PackedStringArray:
	return _failures


func _get_skip_reason() -> String:
	return _skip_reason


static func _both_numbers(a: Variant, b: Variant) -> bool:
	return typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]


static func _show(v: Variant) -> String:
	if v is String:
		return "\"%s\"" % v
	return var_to_str(v).replace("\n", " ")


static func _suffix(msg: String) -> String:
	return "" if msg.is_empty() else " — " + msg
