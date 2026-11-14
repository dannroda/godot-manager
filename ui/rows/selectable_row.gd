class_name SelectableRow
extends PanelContainer
## Base de las filas de las listas: emite `selected` al hacer clic (o al
## recibir el foco), `activated` con doble clic o Enter y `context_requested`
## con clic derecho, la tecla Menú o Shift+F10; cambia el estilo con el hover
## y la selección. La pantalla decide qué hacer.

signal selected(row: Control)
signal activated(row: Control)
## `at`: dónde abrir el menú, en coordenadas de la ventana.
signal context_requested(row: Control, at: Vector2)

var is_selected := false:
	set(value):
		is_selected = value
		_update_style()

var _hovered := false


func _ready() -> void:
	mouse_entered.connect(func() -> void:
		_hovered = true
		_update_style())
	mouse_exited.connect(func() -> void:
		_hovered = false
		_update_style())
	focus_entered.connect(func() -> void: selected.emit(self))


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		selected.emit(self)
		if mb.double_click:
			activated.emit(self)
		accept_event()
	elif mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		grab_focus()
		selected.emit(self)
		context_requested.emit(self, get_global_transform_with_canvas() * mb.position)
		accept_event()
	elif _is_menu_key(event):
		selected.emit(self)
		# Con el teclado, abajo a la izquierda de la fila.
		context_requested.emit(self, get_global_transform_with_canvas() * Vector2(16, size.y))
		accept_event()
	elif event.is_action_pressed("ui_accept"):
		activated.emit(self)
		accept_event()


func _update_style() -> void:
	if is_selected:
		theme_type_variation = &"RowPanelSelected"
	elif _hovered:
		theme_type_variation = &"RowPanelHover"
	else:
		theme_type_variation = &"RowPanel"


static func _is_menu_key(event: InputEvent) -> bool:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return false
	return k.keycode == KEY_MENU or (k.keycode == KEY_F10 and k.shift_pressed)
