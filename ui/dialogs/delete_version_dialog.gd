extends ConfirmationDialog
## Confirmación de Borrar: nombre, carpeta que se borra, aviso si es la default
## y casilla para borrar también sus export templates (sin tildar).
## `open_for(version)` lo llena y lo muestra; al confirmar emite
## `delete_requested` con los argumentos de `remove` ya armados.

signal delete_requested(args: PackedStringArray)

var version: InstalledVersion

@onready var _name: Label = %VersionName
@onready var _folder: Label = %Folder
@onready var _default_warning: Label = %DefaultWarning
@onready var _templates: CheckBox = %RemoveTemplates


func _ready() -> void:
	confirmed.connect(func() -> void: delete_requested.emit(command()))


## Llena el diálogo para `v` (la casilla vuelve a quedar sin tildar).
func fill(v: InstalledVersion) -> void:
	version = v
	_name.text = v.name
	_folder.text = folder_of(v)
	_folder.tooltip_text = _folder.text
	_default_warning.visible = v.is_default
	_templates.button_pressed = false


func open_for(v: InstalledVersion) -> void:
	fill(v)
	reset_size()
	popup_centered()
	get_cancel_button().grab_focus()


## Los argumentos de `remove` según la casilla.
func command() -> PackedStringArray:
	return GmCommands.remove(version.name, _templates.button_pressed)


## La carpeta de la versión: el directorio de su ejecutable.
static func folder_of(v: InstalledVersion) -> String:
	return v.path.get_base_dir()
