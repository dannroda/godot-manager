extends ConfirmationDialog
## Instalar una versión: editor normal o Mono, símbolos de debug y export
## templates por plataforma, con la línea de comando exacta abajo. Lo que la
## release no trae (según `list-remote`) queda deshabilitado; si el CLI no
## informa, todo queda habilitado y decide el CLI.
## `open_install(release)` lo llena y lo muestra; al confirmar emite
## `install_requested` con los argumentos y un título para el panel.

signal install_requested(args: PackedStringArray, title: String)

const NOT_IN_RELEASE := "Esta versión no lo trae para este sistema."

var options := InstallOptions.new()
var release: RemoteVersion

var _platform_boxes := {}

@onready var _version: Label = %VersionName
@onready var _normal: CheckBox = %Normal
@onready var _mono: CheckBox = %Mono
@onready var _symbols: CheckBox = %Symbols
@onready var _templates: CheckBox = %Templates
@onready var _grid: GridContainer = %PlatformGrid
@onready var _command: Label = %Command
@onready var _size: Label = %Size
@onready var _hint: Label = %Hint


func _ready() -> void:
	var group := ButtonGroup.new()
	_normal.button_group = group
	_mono.button_group = group
	for p in GmCommands.PLATFORMS:
		var box := CheckBox.new()
		box.text = p
		box.toggled.connect(func(_on: bool) -> void: _read_ui())
		_grid.add_child(box)
		_platform_boxes[p] = box
	_mono.toggled.connect(func(_on: bool) -> void: _read_ui())
	_symbols.toggled.connect(func(_on: bool) -> void: _read_ui())
	_templates.toggled.connect(func(on: bool) -> void:
		# Al activar templates arrancan todas tildadas.
		if on:
			for box: CheckBox in _platform_boxes.values():
				box.set_pressed_no_signal(true)
		_read_ui())
	confirmed.connect(func() -> void:
		if options.problem().is_empty():
			install_requested.emit(options.command(), title_for(options)))


## Llena el diálogo para instalar `r`, con todo sin tildar. Si `default_mono`
## es true (y la release trae Mono), arranca con Mono marcada.
func fill(r: RemoteVersion, default_mono := false) -> void:
	release = r
	options = InstallOptions.new()
	options.version = r.tag
	_version.text = r.tag
	title = tr("Instalar %s") % r.tag
	ok_button_text = tr("Instalar")
	_set_install_mode(true)
	var want_mono := default_mono and r.mono
	_normal.set_pressed_no_signal(not want_mono)
	_mono.set_pressed_no_signal(want_mono)
	_symbols.set_pressed_no_signal(false)
	_templates.set_pressed_no_signal(false)
	_set_available(_mono, r.mono)
	_set_available(_symbols, r.debug_symbols)
	_label_platforms([])
	_read_ui()


## Modo templates (2.5): para una versión instalada, sin elegir edición (sale
## de la versión) y con las plataformas que ya tiene marcadas y sin tildar.
func fill_templates(v: InstalledVersion) -> void:
	release = null
	options = InstallOptions.for_templates(v)
	_version.text = v.name
	title = tr("Export templates de %s") % v.name
	ok_button_text = tr("Instalar templates")
	_set_install_mode(false)
	_normal.set_pressed_no_signal(not v.mono)
	_mono.set_pressed_no_signal(v.mono)
	_symbols.set_pressed_no_signal(false)
	_set_available(_symbols, true)
	_templates.set_pressed_no_signal(true)
	for p: String in _platform_boxes:
		(_platform_boxes[p] as CheckBox).set_pressed_no_signal(p in options.platforms)
	_label_platforms(v.template_platforms)
	_read_ui()


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


## En modo templates no se elige edición ni se prende/apaga "Export templates".
func _set_install_mode(install: bool) -> void:
	%EditionRow.visible = install
	_templates.visible = install
	_symbols.text = tr("Símbolos de debug") if install else tr("Símbolos de debug de los templates")


## "linux (instalado)" en las que ya están.
func _label_platforms(installed: PackedStringArray) -> void:
	for p: String in _platform_boxes:
		(_platform_boxes[p] as CheckBox).text = (tr("%s (instalado)") % p) if p in installed else p


## "Instalando 4.8-beta3 (mono)", para el panel de progreso.
static func title_for(o: InstallOptions) -> String:
	var what := o.version + (" (mono)" if o.mono else "")
	if o.mode == InstallOptions.Mode.INSTALL:
		return TranslationServer.translate("Instalando %s") % what
	return TranslationServer.translate("Instalando templates de %s") % what


## Pasa lo que hay en pantalla a `options` y actualiza lo que depende de eso.
func _read_ui() -> void:
	options.mono = _mono.button_pressed
	options.debug_symbols = _symbols.button_pressed
	# Templates mono y normales son archivos distintos: depende de la edición.
	var has_templates := release == null or (release.mono_templates if options.mono else release.templates)
	_set_available(_templates, has_templates)
	if not has_templates:
		_templates.set_pressed_no_signal(false)
	options.with_templates = _templates.button_pressed
	var chosen: PackedStringArray = []
	for p: String in _platform_boxes:
		if (_platform_boxes[p] as CheckBox).button_pressed:
			chosen.append(p)
	options.platforms = chosen
	_grid.visible = options.wants_templates()
	_command.text = CliJob.format_command(options.command())
	var bytes := options.download_size(release)
	var size_fmt := tr("Descarga: %s + símbolos") if options.debug_symbols else tr("Descarga: %s")
	_size.text = size_fmt % String.humanize_size(bytes) if bytes > 0 else ""
	_size.visible = bytes > 0
	var why := options.problem()
	_hint.text = why
	_hint.visible = not why.is_empty()
	get_ok_button().disabled = not why.is_empty()
	reset_size()


static func _set_available(box: CheckBox, available: bool) -> void:
	box.disabled = not available
	box.tooltip_text = "" if available else NOT_IN_RELEASE
	if not available:
		box.set_pressed_no_signal(false)
