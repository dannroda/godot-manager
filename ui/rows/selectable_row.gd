class_name SelectableRow
extends PanelContainer
## Base de las filas de las listas: emite `selected` al hacer clic (o al
## recibir el foco) y `activated` con doble clic o Enter; cambia el estilo con
## el hover y la selección. La pantalla decide qué hacer.

signal selected(row: Control)
signal activated(row: Control)

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
