class_name ListState
extends CenterContainer
## Lo que se ve en lugar de una lista sin filas: cargando (con barra
## indeterminada), vacía o error, con un mensaje y botones de acción
## ("Ir a Descargar", "Reintentar"…). La pantalla lo pone encima de la lista.

enum Kind { INFO, LOADING, ERROR }

const ERROR_COLOR := Color(1.0, 0.54, 0.5)

var kind := Kind.INFO
## El mensaje que se ve (lo leen los tests y game_ui).
var text: String:
	get:
		return _message.text if _message != null else ""

@onready var _message: Label = %Message
@onready var _progress: ProgressBar = %Progress
@onready var _actions: HBoxContainer = %Actions


## Muestra el estado. `actions`: pares [texto, Callable]; el primero queda
## como botón principal y toma el foco si la lista lo tenía.
func show_state(message: String, p_kind := Kind.INFO, actions: Array = []) -> void:
	kind = p_kind
	_message.text = message
	_progress.visible = p_kind == Kind.LOADING
	if p_kind == Kind.ERROR:
		_message.add_theme_color_override(&"font_color", ERROR_COLOR)
	else:
		_message.remove_theme_color_override(&"font_color")
	for child in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()
	for a: Array in actions:
		var b := Button.new()
		b.text = a[0]
		b.pressed.connect(a[1])
		_actions.add_child(b)
	_actions.visible = not actions.is_empty()
	visible = true


## El primer botón (para dar el foco con el teclado), o null.
func first_action() -> Button:
	return _actions.get_child(0) as Button if _actions.get_child_count() > 0 else null


## Los textos de los botones, en orden.
func action_labels() -> PackedStringArray:
	var out := PackedStringArray()
	for b: Button in _actions.get_children():
		if not b.is_queued_for_deletion():
			out.append(b.text)
	return out
