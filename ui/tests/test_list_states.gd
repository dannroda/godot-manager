extends TestCase
## 4.2: estados de las listas (cargando / vacía con acción / error con
## Reintentar) en Versiones, contra el CLI real con un GODOT_DIR vacío.

const INSTALLED := preload("res://screens/installed_screen.tscn")

var fx: CliFixture
var screen: Control
var _old_binary := ""
var _old_available := false


func before_each() -> void:
	fx = CliFixture.new()
	if not fx.available():
		skip(fx.why_unavailable())
		return
	fx.setup()
	_old_binary = GmCli.binary
	_old_available = GmCli.available
	GmCli.binary = fx.gm_bin
	GmCli.available = true


func after_each() -> void:
	if screen != null:
		screen.queue_free()
		screen = null
		await wait_frames(1)
	if fx != null and fx.available():
		GmCli.binary = _old_binary
		GmCli.available = _old_available
		fx.teardown()


func _open() -> ListState:
	screen = INSTALLED.instantiate()
	tree.root.add_child(screen)
	screen.refresh()  # En la app lo dispara mostrar la pestaña.
	return screen.get_node("%Placeholder")


func _wait_loaded() -> void:
	for i in 300:
		if screen._loading != null and screen._loading.is_done():
			break
		await wait_frames(1)
	await wait_frames(1)


func test_loading_then_empty_with_actions() -> void:
	if not fx.available():
		return
	var state := _open()
	assert_eq(state.kind, ListState.Kind.LOADING, "mientras corre `list`")
	assert_true(state.visible)
	await _wait_loaded()
	assert_eq(state.kind, ListState.Kind.INFO)
	assert_eq(state.text, "No hay versiones instaladas.")
	assert_eq(state.action_labels(), PackedStringArray(["Ir a Descargar", "Agregar build propio"]))
	var asked: Array[StringName] = []
	screen.tab_requested.connect(func(t: StringName) -> void: asked.append(t))
	state.first_action().pressed.emit()
	assert_eq(asked, [&"remote"] as Array[StringName])
	assert_true((screen.get_node("%Delete") as Button).disabled, "sin selección, acciones apagadas")


func test_error_with_retry() -> void:
	if not fx.available():
		return
	GmCli.binary = CliFixture.fake_executable().get_base_dir().path_join("false")
	var state := _open()
	await _wait_loaded()
	assert_eq(state.kind, ListState.Kind.ERROR)
	assert_has(state.text, "No se pudo cargar la lista")
	assert_eq(state.action_labels(), PackedStringArray(["Reintentar"]))
	GmCli.binary = fx.gm_bin
	state.first_action().pressed.emit()
	await _wait_loaded()
	assert_eq(state.text, "No hay versiones instaladas.", "Reintentar vuelve a pedir la lista")
