extends SelectableRow
## Fila de un proyecto: ícono, nombre, ruta y la versión de Godot con que se
## creó. La versión que usa (3.2) la pone la pantalla con `set_uses`.

const TAG_SCENE := preload("res://rows/tag.tscn")
const DEFAULT_ICON := preload("res://icon.svg")
const ICON_SIZE := 48
const ERROR_COLOR := Color(1.0, 0.47, 0.42)

## Pide instalar la versión fijada que falta.
signal install_requested(version: String)

var project: ProjectEntry
var status: ProjectStatus

@onready var _install: Button = %Install
@onready var _icon: TextureRect = %Icon
@onready var _name: Label = %Name
@onready var _tags: HBoxContainer = %Tags
@onready var _path: Label = %Path
@onready var _uses: Label = %Uses


func _ready() -> void:
	super()
	_install.pressed.connect(func() -> void:
		if status != null and not status.missing_version().is_empty():
			install_requested.emit(status.missing_version()))
	if project != null:
		_fill()


func setup(e: ProjectEntry) -> void:
	project = e
	if is_node_ready():
		_fill()


## La versión que usa (3.2), a la derecha; null la oculta. Si la fijada no
## está instalada, aparece el botón Instalar….
func set_status(s: ProjectStatus) -> void:
	status = s
	if not is_node_ready():
		return
	_uses.visible = s != null
	_install.visible = s != null and not s.missing_version().is_empty()
	if s == null:
		return
	_uses.text = s.text()
	_uses.tooltip_text = s.tooltip()
	if s.is_error():
		_uses.add_theme_color_override(&"font_color", ERROR_COLOR)
	else:
		_uses.remove_theme_color_override(&"font_color")
	_install.tooltip_text = "Instalar %s" % s.missing_version()


func _fill() -> void:
	_name.text = project.name
	_path.text = project.path
	_path.tooltip_text = project.path
	_icon.texture = load_icon(project.icon_path)
	for child in _tags.get_children():
		child.queue_free()
	var made := project.created_with()
	if not made.is_empty():
		_add_tag(made, "Versión de Godot con que se guardó el proyecto (config/features)")
	if project.missing:
		_add_tag("No encontrado", "La carpeta o su project.godot ya no existen")
	elif project.unreadable:
		_add_tag("project.godot ilegible", "No se pudo leer project.godot")
	modulate.a = 0.55 if project.missing else 1.0
	set_status(status)


func _add_tag(text: String, tooltip: String) -> void:
	var tag := TAG_SCENE.instantiate()
	(tag.get_node("Text") as Label).text = text
	tag.tooltip_text = tooltip
	# Para que se vea el tooltip; el clic sigue llegando a la fila.
	tag.mouse_filter = Control.MOUSE_FILTER_PASS
	_tags.add_child(tag)


## El ícono del proyecto achicado a ICON_SIZE, o el de Godot si no tiene o no
## se puede cargar (PNG, SVG, WebP, JPG: lo que lea Image).
## Se guardan por ruta y fecha, así filtrar o reordenar no vuelve a leerlos.
static func load_icon(path: String) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return DEFAULT_ICON
	var key := "%s|%d" % [path, FileAccess.get_modified_time(path)]
	if not _icon_cache.has(key):
		_icon_cache[key] = _read_icon(path)
	return _icon_cache[key]


static var _icon_cache := {}


static func _read_icon(path: String) -> Texture2D:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return DEFAULT_ICON
	var longest := maxi(img.get_width(), img.get_height())
	if longest > ICON_SIZE:
		var f := float(ICON_SIZE) / longest
		img.resize(maxi(1, roundi(img.get_width() * f)), maxi(1, roundi(img.get_height() * f)),
			Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)
