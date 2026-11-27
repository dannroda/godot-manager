extends TestCase
## Barra lateral de main: cambiar de sección por código (como hacen Ctrl+Tab y
## «Ir a Descargar») deja marcada solo esa sección, y los atajos van a ella.

const MAIN := preload("res://main.tscn")

var main: Control
var _history_before := 0


func before_each() -> void:
	_history_before = GmCli.history.size()
	main = MAIN.instantiate()
	# Sin los Ajustes reales ni el CLI: los tests no corren comandos de verdad.
	main.check_cli_on_ready = false
	tree.root.add_child(main)


func after_each() -> void:
	main.queue_free()
	await wait_frames(1)


func test_does_not_run_the_cli() -> void:
	# Con check_cli_on_ready apagado, levantar main no lanza comandos.
	await wait_frames(3)
	assert_eq(GmCli.history.size(), _history_before)
	assert_false(GmCli.available)


func test_show_screen_marks_only_that_section() -> void:
	for index in [2, 1, 0]:
		main._show_screen(index)
		var pressed: Array[bool] = []
		for b: Button in main._nav:
			pressed.append(b.button_pressed)
		var expected: Array[bool] = [index == 0, index == 1, index == 2]
		assert_eq(pressed, expected, "sección %d" % index)
		assert_eq(main.current_screen(), index)
		assert_true(main._screens[index].visible)
