class_name RowMenu
extends RefCounted
## Menú contextual de una fila (clic derecho, tecla Menú o Shift+F10). Repite
## los botones de acciones de la pantalla (los visibles): cada ítem es un botón, con su texto
## y su estado (deshabilitado si el botón lo está), y elegirlo es apretarlo.
## Así el menú y la columna de acciones nunca se contradicen.

const MENU_NAME := &"RowContextMenu"


## Muestra el menú en `at` (coordenadas de la ventana) con `buttons`; null en la
## lista es un separador. Devuelve el PopupMenu (lo usan los tests).
static func popup(owner: Control, buttons: Array, at: Vector2) -> PopupMenu:
	var menu := owner.get_node_or_null(NodePath(MENU_NAME)) as PopupMenu
	if menu == null:
		menu = PopupMenu.new()
		menu.name = MENU_NAME
		owner.add_child(menu)
		menu.id_pressed.connect(func(id: int) -> void:
			var b: Variant = menu.get_meta(&"buttons", [])[id]
			if is_instance_valid(b) and not (b as BaseButton).disabled:
				(b as BaseButton).pressed.emit())
	fill(menu, buttons)
	menu.reset_size()
	menu.popup(Rect2i(popup_position(owner, menu, at), Vector2i.ZERO))
	return menu


## Dónde abrir el menú. Embebido, en coordenadas de la ventana (`at`); como
## ventana propia (los diálogos y menús de la app lo son), en coordenadas de la
## pantalla, como Control.get_screen_position(): con la posición de la ventana
## y su escala (Viewport.get_screen_transform() no suma la posición).
static func popup_position(owner: Control, menu: Window, at: Vector2) -> Vector2i:
	if menu.is_embedded():
		return Vector2i(at)
	var to_screen := owner.get_screen_transform() * owner.get_global_transform_with_canvas().affine_inverse()
	return Vector2i(to_screen * at)


## Llena `menu` con `buttons` (sin mostrarlo).
static func fill(menu: PopupMenu, buttons: Array) -> void:
	menu.clear()
	menu.set_meta(&"buttons", buttons)
	for i in buttons.size():
		var b := buttons[i] as Button
		if b == null:
			menu.add_separator()
			continue
		if not b.visible:
			continue
		menu.add_item(b.text, i)
		var index := menu.get_item_index(i)
		menu.set_item_disabled(index, b.disabled)
		menu.set_item_tooltip(index, b.tooltip_text)
	# Sin separadores al principio, al final ni dos seguidos (si la lista
	# los traía por botones que la pantalla no tiene).
	var i := menu.item_count - 1
	while i >= 0:
		var sep := menu.is_item_separator(i)
		if sep and (i == 0 or i == menu.item_count - 1 or menu.is_item_separator(i - 1)):
			menu.remove_item(i)
		i -= 1
