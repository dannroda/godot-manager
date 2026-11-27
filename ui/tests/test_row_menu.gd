extends TestCase
## Menú contextual de las filas: repite los botones de acciones (texto,
## deshabilitado, separadores) y elegir un ítem es apretar el botón. También
## el clic derecho y Shift+F10 sobre una fila real de Proyectos.

const SCREEN := preload("res://screens/projects_screen.tscn")
const CFG := "user://test_row_menu.cfg"

var holder: Control
var pressed: Array[String] = []


func before_each() -> void:
	holder = Control.new()
	tree.root.add_child(holder)
	pressed.clear()


func after_each() -> void:
	holder.queue_free()
	await wait_frames(1)


func _button(text: String, disabled := false) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.pressed.connect(func() -> void: pressed.append(text))
	holder.add_child(b)
	return b


func _texts(menu: PopupMenu) -> PackedStringArray:
	var out := PackedStringArray()
	for i in menu.item_count:
		out.append("---" if menu.is_item_separator(i) else menu.get_item_text(i))
	return out


func test_items_mirror_buttons() -> void:
	var open := _button("Abrir")
	var run := _button("Correr", true)
	var del := _button("Borrar")
	var hidden := _button("Instalar")
	hidden.visible = false
	var menu := PopupMenu.new()
	holder.add_child(menu)
	RowMenu.fill(menu, [hidden, null, open, run, null, null, del, null])
	assert_eq(_texts(menu), PackedStringArray(["Abrir", "Correr", "---", "Borrar"]), "sin ocultos ni separadores de más")
	assert_false(menu.is_item_disabled(0))
	assert_true(menu.is_item_disabled(1))


func test_choosing_presses_button() -> void:
	var open := _button("Abrir")
	var run := _button("Correr", true)
	var menu := RowMenu.popup(holder, [open, run], Vector2(10, 10))
	menu.id_pressed.emit(menu.get_item_id(0))
	menu.id_pressed.emit(menu.get_item_id(1))
	assert_eq(pressed, ["Abrir"] as Array[String], "el deshabilitado no se aprieta")
	# Se reusa el mismo menú.
	assert_eq(RowMenu.popup(holder, [open], Vector2.ZERO), menu)
	menu.hide()


func test_right_click_and_keyboard_on_project_row() -> void:
	var dir := ProjectSettings.globalize_path("user://test_row_menu_project")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("project.godot"), FileAccess.WRITE)
	f.store_string("config_version=5\n\n[application]\n\nconfig/name=\"Menú\"\n")
	f.close()
	var screen := SCREEN.instantiate()
	screen.list_path = CFG
	tree.root.add_child(screen)
	screen.add_project(dir)
	var row: Control = screen.get_node("%Rows").get_child(0)
	screen._select(null)
	for r in screen.get_node("%Rows").get_children():
		r.is_selected = false

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	click.position = Vector2(5, 5)
	row._gui_input(click)
	await wait_frames(1)
	assert_eq(screen.selected.name, "Menú", "el clic derecho selecciona")
	var menu := screen.get_node_or_null("RowContextMenu") as PopupMenu
	if not assert_true(menu != null and menu.visible, "se abrió el menú"):
		screen.queue_free()
		return
	var texts := _texts(menu)
	assert_eq(texts[0], "Abrir")
	assert_eq(texts[texts.size() - 1], "Quitar de la lista")
	menu.hide()
	await wait_frames(2)

	var key := InputEventKey.new()
	key.keycode = KEY_F10
	key.shift_pressed = true
	key.pressed = true
	row._gui_input(key)
	await wait_frames(1)
	assert_true(menu.visible, "Shift+F10 también lo abre")
	menu.hide()

	screen.queue_free()
	await wait_frames(1)
	DirAccess.remove_absolute(dir.path_join("project.godot"))
	DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
