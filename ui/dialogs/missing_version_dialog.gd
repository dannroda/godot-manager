extends AcceptDialog
## Un proyecto pide una versión que no está instalada: ofrece instalarla,
## elegir otra de las instaladas o usar la default. No corre nada: emite
## `choice` y la pantalla de Proyectos hace el resto (instalar, set-local).

## `kind`: INSTALL, OTHER o DEFAULT.
signal choice(kind: StringName)

const INSTALL := &"install"
const OTHER := &"other"
const DEFAULT := &"default"

var _other: Button
var _default: Button

@onready var _message: Label = %Message


func _ready() -> void:
	_other = add_button(tr("Elegir otra versión…"), false, OTHER)
	_default = add_button(tr("Usar la default"), false, DEFAULT)
	add_cancel_button(tr("Cancelar"))
	confirmed.connect(func() -> void: choice.emit(INSTALL))
	custom_action.connect(func(action: StringName) -> void:
		hide()
		choice.emit(action))


## `default_name`: la default instalada ("" si no hay, o si la que falta es la
## default misma); `installed`: cuántas versiones hay instaladas.
func fill(project_name: String, missing: String, default_name: String, installed: int, missing_is_default := false) -> void:
	if missing_is_default:
		_message.text = tr("«%s» usa la versión default, %s, que no está instalada.") % [project_name, missing]
	else:
		_message.text = tr("«%s» está fijado a %s, que no está instalada.") % [project_name, missing]
	get_ok_button().text = tr("Instalar %s") % missing
	_other.disabled = installed == 0
	_other.tooltip_text = tr("No hay otras versiones instaladas.") if installed == 0 \
		else tr("Fija el proyecto a una de las versiones instaladas")
	_default.visible = not missing_is_default
	_default.disabled = default_name.is_empty()
	_default.text = (tr("Usar la default (%s)") % default_name) if not default_name.is_empty() else tr("Usar la default")
	_default.tooltip_text = tr("No hay una versión default instalada.") if default_name.is_empty() \
		else tr("El proyecto pasa a abrirse con la default")


func open_for(project_name: String, missing: String, default_name: String, installed: int, missing_is_default := false) -> void:
	fill(project_name, missing, default_name, installed, missing_is_default)
	reset_size()
	popup_centered()
	get_ok_button().grab_focus()
