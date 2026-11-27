extends ConfirmationDialog
## Instalar una versión (o sus export templates) en un diálogo: el formulario
## de InstallForm con Instalar/Cancelar. `open_install(release)` y
## `open_templates(version)` lo llenan y lo muestran; al confirmar emite
## `install_requested` con los argumentos y un título para el panel.

signal install_requested(args: PackedStringArray, title: String)

## Lo que está elegido en el formulario.
var options: InstallOptions:
	get:
		return form.options

@onready var form: InstallForm = %Form


func _ready() -> void:
	form.changed.connect(func() -> void:
		get_ok_button().disabled = not form.problem().is_empty()
		reset_size())
	confirmed.connect(func() -> void:
		if form.problem().is_empty():
			install_requested.emit(options.command(), title_for(options)))


func fill(r: RemoteVersion, default_mono := false) -> void:
	title = tr("Instalar %s") % r.tag
	ok_button_text = tr("Instalar")
	form.fill(r, default_mono)


func fill_templates(v: InstalledVersion) -> void:
	title = tr("Export templates de %s") % v.name
	ok_button_text = tr("Instalar templates")
	form.fill_templates(v)


func open_install(r: RemoteVersion, default_mono := false) -> void:
	fill(r, default_mono)
	_popup()


func open_templates(v: InstalledVersion) -> void:
	fill_templates(v)
	_popup()


func _popup() -> void:
	reset_size()
	popup_centered()
	get_ok_button().grab_focus()


static func title_for(o: InstallOptions) -> String:
	return InstallForm.title_for(o)
