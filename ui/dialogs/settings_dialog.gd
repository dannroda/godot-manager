extends ConfirmationDialog
## Ajustes: binario de godot-manager, GITHUB_TOKEN y GODOT_DIR.
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
@onready var _binary_dialog: FileDialog = %BinaryFileDialog
@onready var _dir_dialog: FileDialog = %DirFileDialog

## Dónde se guarda (los tests lo cambian).
var settings_path := AppSettings.PATH


func _ready() -> void:
	var group := ButtonGroup.new()
	_use_path.button_group = group
	_use_fixed.button_group = group
	if OS.get_name() == "Windows":
		_binary_dialog.filters = PackedStringArray(["*.exe ; Ejecutables"])
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
		_show_token.text = "Ocultar" if on else "Ver")
	%BrowseDir.pressed.connect(func() -> void:
		if not _godot_dir.text.is_empty():
			_dir_dialog.current_dir = _godot_dir.text
		_dir_dialog.popup_centered())
	_dir_dialog.dir_selected.connect(func(dir: String) -> void: _godot_dir.text = dir)
	confirmed.connect(_save)


func open_with(settings: AppSettings) -> void:
	_use_fixed.button_pressed = settings.binary_mode == AppSettings.BinaryMode.FIXED
	_use_path.button_pressed = settings.binary_mode == AppSettings.BinaryMode.SEARCH_PATH
	_binary_path.text = settings.binary_path
	_token.text = settings.github_token
	_show_token.button_pressed = false
	_godot_dir.text = settings.godot_dir
	_clear_test()
	_update_enabled()
	popup_centered()


## Los ajustes como están en el formulario.
func current_settings() -> AppSettings:
	var s := AppSettings.new()
	s.binary_mode = AppSettings.BinaryMode.FIXED if _use_fixed.button_pressed else AppSettings.BinaryMode.SEARCH_PATH
	s.binary_path = _binary_path.text.strip_edges()
	s.github_token = _token.text.strip_edges()
	s.godot_dir = _godot_dir.text.strip_edges()
	return s


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
	_test_result.text = "Probando…"
	_test_result.remove_theme_color_override("font_color")
	var r: GmResult = await GmCli.probe(binary)
	_test_binary.disabled = false
	if r.ok:
		_test_result.text = "godot-manager %s" % r.value
		_test_result.add_theme_color_override("font_color", Color("#8fd18f"))
	else:
		_test_result.text = r.error.message
		_test_result.add_theme_color_override("font_color", Color("#ff8a80"))


func _save() -> void:
	var s := current_settings()
	var err := s.save(settings_path)
	if err != OK:
		push_error("No se pudieron guardar los ajustes en %s: %s" % [settings_path, error_string(err)])
	s.apply_to(GmCli)
	saved.emit(s)
