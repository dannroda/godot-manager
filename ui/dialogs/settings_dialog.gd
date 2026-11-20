extends ConfirmationDialog
## Ajustes: binario de godot-manager, GITHUB_TOKEN y GODOT_DIR (la carpeta de
## versiones: muestra la por defecto, que se guarda como vacía); y si
## godot-manager está en el PATH (eso se aplica enseguida, no al Guardar).
## `open_with(settings)` lo llena; al Guardar escribe settings.cfg, aplica a
## GmCli y emite `saved`.

signal saved(settings: AppSettings)

@onready var _use_path: CheckBox = %UsePath
@onready var _use_fixed: CheckBox = %UseFixed
@onready var _binary_path: LineEdit = %BinaryPath
@onready var _browse_binary: Button = %BrowseBinary
@onready var _test_binary: Button = %TestBinary
@onready var _test_result: Label = %TestResult
@onready var _token: LineEdit = %Token
@onready var _show_token: Button = %ShowToken
@onready var _godot_dir: LineEdit = %GodotDir
@onready var _reset_dir: Button = %ResetDir
@onready var _dir_help: Label = %DirHelp
@onready var _check_updates: CheckBox = %CheckUpdates
@onready var _path_status: Label = %PathStatus
@onready var _path_button: Button = %PathButton
## Lo último que dijo `path` (null mientras carga o si falló).
var path_status: PathStatus
## Los ajustes con que se abrió (para lo que el formulario no muestra).
var _opened_with: AppSettings
## La carpeta que usa el CLI sin GODOT_DIR ("" si no se sabe: CLI viejo o sin CLI).
var default_dir := ""
@onready var _binary_dialog: FileDialog = %BinaryFileDialog
@onready var _dir_dialog: FileDialog = %DirFileDialog

## Dónde se guarda (los tests lo cambian).
var settings_path := AppSettings.PATH


func _ready() -> void:
	var group := ButtonGroup.new()
	_use_path.button_group = group
	_use_fixed.button_group = group
	if OS.get_name() == "Windows":
		_binary_dialog.filters = PackedStringArray([tr("*.exe ; Ejecutables")])
		_binary_path.placeholder_text = "C:\\ruta\\a\\godot-manager.exe"
	_use_path.toggled.connect(func(_on: bool) -> void: _update_enabled())
	_binary_path.text_changed.connect(func(_t: String) -> void: _clear_test())
	_browse_binary.pressed.connect(_binary_dialog.popup_centered)
	_binary_dialog.file_selected.connect(func(path: String) -> void:
		_binary_path.text = path
		_use_fixed.button_pressed = true
		_clear_test())
	_test_binary.pressed.connect(_run_test)
	_show_token.toggled.connect(func(on: bool) -> void:
		_token.secret = not on
		_show_token.text = tr("Ocultar") if on else tr("Ver"))
	%BrowseDir.pressed.connect(func() -> void:
		if not _godot_dir.text.is_empty():
			_dir_dialog.current_dir = _godot_dir.text
		_dir_dialog.popup_centered())
	_dir_dialog.dir_selected.connect(func(dir: String) -> void:
		_godot_dir.text = dir
		_update_dir())
	_godot_dir.text_changed.connect(func(_t: String) -> void: _update_dir())
	_reset_dir.pressed.connect(func() -> void:
		_godot_dir.text = default_dir
		_update_dir())
	_path_button.pressed.connect(_toggle_path)
	confirmed.connect(_save)


func open_with(settings: AppSettings) -> void:
	_use_fixed.button_pressed = settings.binary_mode == AppSettings.BinaryMode.FIXED
	_use_path.button_pressed = settings.binary_mode == AppSettings.BinaryMode.SEARCH_PATH
	_binary_path.text = settings.binary_path
	_token.text = settings.github_token
	_show_token.button_pressed = false
	_godot_dir.text = settings.godot_dir
	if _godot_dir.text.is_empty():
		_godot_dir.text = default_dir
	_update_dir()
	_check_updates.button_pressed = settings.check_updates
	_opened_with = settings
	_clear_test()
	_update_enabled()
	popup_centered()
	refresh_path()
	refresh_dirs()


## Los ajustes como están en el formulario.
func current_settings() -> AppSettings:
	var s := AppSettings.new()
	s.binary_mode = AppSettings.BinaryMode.FIXED if _use_fixed.button_pressed else AppSettings.BinaryMode.SEARCH_PATH
	s.binary_path = _binary_path.text.strip_edges()
	s.github_token = _token.text.strip_edges()
	s.godot_dir = _godot_dir.text.strip_edges()
	if is_default_dir(s.godot_dir):
		s.godot_dir = ""
	s.check_updates = _check_updates.button_pressed
	if _opened_with != null:
		s.last_update_check = _opened_with.last_update_check
	return s


## Pregunta `dirs` por la carpeta por defecto; con el campo vacío la muestra.
func refresh_dirs() -> void:
	if not GmCli.available:
		return
	var job := GmCli.read(GmCommands.dirs())
	job.notify_on_error = false
	await job.finished
	var r := GmParse.parse_dirs(job.stdout) if job.succeeded() else null
	if r == null or not r.ok:
		return
	set_default_dir((r.value as Dictionary).default_godot_dir)


func set_default_dir(dir: String) -> void:
	default_dir = dir
	if _godot_dir.text.strip_edges().is_empty():
		_godot_dir.text = dir
	_update_dir()


## Si `dir` es la carpeta por defecto (vacío también lo es).
func is_default_dir(dir: String) -> bool:
	dir = dir.strip_edges()
	if dir.is_empty():
		return true
	if default_dir.is_empty():
		return false
	var a := _clean_dir(dir)
	var b := _clean_dir(default_dir)
	if OS.get_name() in ["Windows", "macOS"]:
		return a.to_lower() == b.to_lower()
	return a == b


static func _clean_dir(dir: String) -> String:
	return dir.replace("\\", "/").simplify_path().trim_suffix("/")


func _update_dir() -> void:
	var is_default := is_default_dir(_godot_dir.text)
	_reset_dir.disabled = is_default
	if is_default:
		_dir_help.text = tr("Donde godot-manager instala las versiones. Es la carpeta por defecto.")
	elif default_dir.is_empty():
		_dir_help.text = tr("Donde godot-manager instala las versiones (GODOT_DIR). «Restaurar» vuelve a la carpeta por defecto.")
	else:
		_dir_help.text = tr("Donde godot-manager instala las versiones (GODOT_DIR). La carpeta por defecto es %s.") % default_dir


func _update_enabled() -> void:
	var fixed := _use_fixed.button_pressed
	_binary_path.editable = fixed
	_browse_binary.disabled = not fixed
	_clear_test()


func _clear_test() -> void:
	_test_result.text = ""
	_test_result.remove_theme_color_override("font_color")


func _run_test() -> void:
	var binary := current_settings().binary()
	_test_binary.disabled = true
	_test_result.text = tr("Probando…")
	_test_result.remove_theme_color_override("font_color")
	var r: GmResult = await GmCli.probe(binary)
	_test_binary.disabled = false
	if r.ok:
		_test_result.text = "godot-manager %s" % r.value
		_test_result.add_theme_color_override("font_color", Color("#8fd18f"))
	else:
		_test_result.text = r.error.message
		_test_result.add_theme_color_override("font_color", Color("#ff8a80"))


## Pregunta `path` y muestra si godot-manager está en el PATH.
func refresh_path() -> void:
	path_status = null
	show_path_status(null)
	if not GmCli.available:
		_path_status.text = tr("godot-manager no está disponible.")
		return
	var job := GmCli.read(GmCommands.path_status())
	job.notify_on_error = false
	await job.finished
	var r := GmParse.parse_path(job.stdout) if job.succeeded() else null
	if r != null and r.ok:
		path_status = r.value
		show_path_status(path_status)
	else:
		_path_status.text = tr("No se pudo saber si está en el PATH (hace falta godot-manager 2.4 o posterior).")


## Texto y botón para un resultado de `path` (null: cargando).
func show_path_status(st: PathStatus) -> void:
	_path_button.visible = st != null and st.managed.is_empty()
	_path_button.disabled = false
	if st == null:
		_path_status.text = tr("Revisando el PATH…")
		return
	if not st.managed.is_empty():
		_path_status.text = tr("Lo instaló %s, que maneja el PATH.") % st.managed
	elif st.on_path:
		_path_status.text = tr("godot-manager y godot están en el PATH: se pueden usar desde una terminal.")
		_path_button.text = tr("Quitar del PATH")
	else:
		_path_status.text = tr("godot-manager no está en el PATH. Agregarlo permite usar godot-manager y godot desde cualquier terminal (%s).") % st.target
		_path_button.text = tr("Agregar al PATH")


func _toggle_path() -> void:
	if path_status == null:
		return
	_path_button.disabled = true
	var job := GmCli.write(GmCommands.path_change(not path_status.on_path))
	await job.finished
	refresh_path()


func _save() -> void:
	var s := current_settings()
	var err := s.save(settings_path)
	if err != OK:
		push_error("No se pudieron guardar los ajustes en %s: %s" % [settings_path, error_string(err)])
	s.apply_to(GmCli)
	saved.emit(s)
