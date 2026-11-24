extends AcceptDialog
## Un proyecto pide una versión que no está instalada: ofrece instalarla,
## elegir otra de las instaladas o usar la default. No corre nada: emite
## `choice` y la pantalla de Proyectos hace el resto (instalar, set-local).

## `kind`: SUGGESTED, INSTALL, OTHER o DEFAULT.
signal choice(kind: StringName)

const SUGGESTED := &"suggested"
const INSTALL := &"install"
const OTHER := &"other"
const DEFAULT := &"default"

var _other: Button
var _default: Button
var _install_alt: Button
var _suggested_name := ""

@onready var _message: Label = %Message


func _ready() -> void:
	_other = add_button(tr("Elegir otra versión…"), false, OTHER)
	_default = add_button(tr("Usar la default"), false, DEFAULT)
	_install_alt = add_button(tr("Instalar"), false, INSTALL)
	_install_alt.visible = false
	add_cancel_button(tr("Cancelar"))
	confirmed.connect(func() -> void:
		choice.emit(SUGGESTED if not _suggested_name.is_empty() else INSTALL))
	custom_action.connect(func(action: StringName) -> void:
		hide()
		choice.emit(action))


## `default_name`: la default instalada ("" si no hay, o si la que falta es la
## default misma); `installed`: cuántas versiones hay instaladas;
## `suggested_name`: la más nueva instalada del mismo minor ("" si no hay).
func fill(project_name: String, missing: String, default_name: String, installed: int,
		missing_is_default := false, suggested_name := "") -> void:
	_suggested_name = suggested_name
	if missing_is_default:
		_message.text = tr("«%s» usa la versión default, %s, que no está instalada.") % [project_name, missing]
	else:
		_message.text = tr("«%s» está fijado a %s, que no está instalada.") % [project_name, missing]
	if not suggested_name.is_empty():
		get_ok_button().text = tr("Usar %s") % suggested_name
		get_ok_button().tooltip_text = tr("Fija el proyecto a %s") % suggested_name
		_install_alt.visible = true
		_install_alt.text = tr("Instalar %s") % missing
	else:
		get_ok_button().text = tr("Instalar %s") % missing
		get_ok_button().tooltip_text = ""
		_install_alt.visible = false
	_other.disabled = installed == 0
	_other.tooltip_text = tr("No hay otras versiones instaladas.") if installed == 0 \
		else tr("Fija el proyecto a una de las versiones instaladas")
	_default.visible = not missing_is_default
	_default.disabled = default_name.is_empty()
	_default.text = (tr("Usar la default (%s)") % default_name) if not default_name.is_empty() else tr("Usar la default")
	_default.tooltip_text = tr("No hay una versión default instalada.") if default_name.is_empty() \
		else tr("El proyecto pasa a abrirse con la default")


func open_for(project_name: String, missing: String, default_name: String, installed: int,
		missing_is_default := false, suggested_name := "") -> void:
	fill(project_name, missing, default_name, installed, missing_is_default, suggested_name)
	reset_size()
	popup_centered()
	get_ok_button().grab_focus()


## La versión instalada más nueva del mismo major.minor que `missing`
## (respetando mono/normal y nunca más vieja que `missing`), o null si no hay ninguna.
static func best_same_minor(missing: String, installed: Array[InstalledVersion]) -> InstalledVersion:
	var want_mono := missing.ends_with("-mono")
	var missing_tag := missing.trim_suffix("-mono") if want_mono else missing
	var target := GmParse.version_numbers(missing_tag)
	if target[0] <= 0:
		return null
	var best: InstalledVersion = null
	for v in installed:
		if v.name == missing or v.mono != want_mono:
			continue
		var tag := v.tag if not v.tag.is_empty() else v.name
		var nums := GmParse.version_numbers(tag)
		if nums[0] != target[0] or nums[1] != target[1]:
			continue
		if GmParse.is_newer(missing_tag, tag):
			continue
		if best == null or VersionFilter.is_before(v, best):
			best = v
	return best
