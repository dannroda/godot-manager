extends TestCase
## Barra lateral de main: cambiar de sección por código (como hacen Ctrl+Tab y
## «Ir a Descargar») deja marcada solo esa sección, y los atajos van a ella.

const MAIN := preload("res://main.tscn")

var main: Control
## Lo que main pisa en GmCli al arrancar (los Ajustes reales y el chequeo del
## binario); se restaura para que los tests siguientes no vean el CLI real.
var _saved := {}


func before_each() -> void:
	_saved = {"available": GmCli.available, "binary": GmCli.binary, "env": GmCli.env.duplicate(),
		"cli_version": GmCli.cli_version, "availability_message": GmCli.availability_message}
	main = MAIN.instantiate()
	tree.root.add_child(main)


func after_each() -> void:
	# El chequeo es asíncrono: se espera a que termine antes de restaurar.
	await wait_until(func() -> bool: return not (main.get_node("%BannerRetry") as Button).disabled)
	main.queue_free()
	await wait_frames(1)
	for key: String in _saved:
		GmCli.set(key, _saved[key])


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
