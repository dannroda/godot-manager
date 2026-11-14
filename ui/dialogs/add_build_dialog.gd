extends ConfirmationDialog
## Agregar build propio: nombre, ejecutable y "Enlazar en lugar de copiar".
## `open_with(taken)` lo limpia y lo muestra; `taken` son los nombres ya
## instalados. Con un nombre repetido aparece "Reemplazar la existente", y
## sin marcarla no se puede agregar; marcada, va `--force` (CLI 2.2+).
## Al confirmar emite `add_requested` con los argumentos de `add`. Lo demás
## (nombre con `/`, archivo que no es ejecutable) lo valida el CLI.

signal add_requested(args: PackedStringArray)

var taken: PackedStringArray = []

@onready var _name: LineEdit = %BuildName
@onready var _path: LineEdit = %BuildPath
@onready var _symlink: CheckBox = %Symlink
@onready var _hint: Label = %Hint
@onready var _replace: CheckBox = %Replace
@onready var _file_dialog: FileDialog = %BuildFileDialog


func _ready() -> void:
	if OS.get_name() == "Windows":
		_file_dialog.filters = PackedStringArray([tr("*.exe ; Ejecutables")])
	_name.text_changed.connect(func(_t: String) -> void: _validate())
	_path.text_changed.connect(func(_t: String) -> void: _validate())
	_replace.toggled.connect(func(_on: bool) -> void: _validate())
	_name.text_submitted.connect(func(_t: String) -> void: _submit())
	_path.text_submitted.connect(func(_t: String) -> void: _submit())
	%Browse.pressed.connect(func() -> void:
		if not _path.text.is_empty():
			_file_dialog.current_path = _path.text
		_file_dialog.popup_centered_ratio(0.6))
	_file_dialog.file_selected.connect(func(path: String) -> void:
		_path.text = path
		_validate())
	confirmed.connect(func() -> void: add_requested.emit(command()))
	_validate()


## Deja el diálogo vacío, con `names` como nombres ocupados.
func reset(names: PackedStringArray) -> void:
	taken = names
	_name.text = ""
	_path.text = ""
	_symlink.button_pressed = false
	_replace.button_pressed = false
	_validate()


func open_with(names: PackedStringArray) -> void:
	reset(names)
	reset_size()
	popup_centered()
	_name.grab_focus()


func command() -> PackedStringArray:
	return GmCommands.add(_name.text.strip_edges(), _path.text.strip_edges(), _symlink.button_pressed,
		_name_taken() and _replace.button_pressed)


## Por qué no se puede agregar todavía ("" si se puede).
func problem() -> String:
	var bin_name := _name.text.strip_edges()
	if bin_name.is_empty():
		return tr("Poné un nombre para la versión.")
	if _name_taken() and not _replace.button_pressed:
		return tr("Ya hay una versión llamada «%s».") % bin_name
	if _path.text.strip_edges().is_empty():
		return tr("Elegí el ejecutable de Godot.")
	return ""


func _name_taken() -> bool:
	return _name.text.strip_edges() in taken


func _validate() -> void:
	var why := problem()
	var replacing := _name_taken() and _replace.button_pressed
	_hint.text = why
	if why.is_empty() and replacing:
		_hint.text = tr("Se borra la versión «%s» actual y queda esta en su lugar.") % _name.text.strip_edges()
	_replace.visible = _name_taken()
	get_ok_button().disabled = not why.is_empty()
	ok_button_text = tr("Reemplazar") if replacing else tr("Agregar")


func _submit() -> void:
	if problem().is_empty():
		hide()
		confirmed.emit()
