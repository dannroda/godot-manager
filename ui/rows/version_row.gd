extends SelectableRow
## Fila de una versión instalada.

const TAG_SCENE := preload("res://rows/tag.tscn")

var version: InstalledVersion
## La más nueva de su serie, si hay (de `outdated`).
var update: VersionUpdate

@onready var _star: Label = %Star
@onready var _name: Label = %Name
@onready var _tags: HBoxContainer = %Tags
@onready var _path: Label = %Path


func _ready() -> void:
	super()
	if version != null:
		_fill()


func setup(v: InstalledVersion, p_update: VersionUpdate = null) -> void:
	version = v
	update = p_update
	if is_node_ready():
		_fill()


func _fill() -> void:
	_star.modulate.a = 1.0 if version.is_default else 0.0
	_star.tooltip_text = tr("Versión por defecto") if version.is_default else ""
	_name.text = version.name
	_path.text = version.path
	_path.tooltip_text = version.path
	for child in _tags.get_children():
		child.queue_free()
	if version.mono:
		_add_tag(tr("Mono"))
	if version.debug_symbols:
		_add_tag(tr("Símbolos"))
	if version.custom:
		_add_tag(tr("Build propio"))
	if not version.template_platforms.is_empty():
		_add_tag(tr("Templates: %s") % ", ".join(version.template_platforms))
	if update != null:
		var tag := _add_tag(tr("Nueva: %s") % update.latest)
		tag.tooltip_text = tr("Ya está instalada") if update.installed \
			else tr("Hay una versión más nueva de esta serie: Actualizar la instala")


func _add_tag(text: String) -> Control:
	var tag: Control = TAG_SCENE.instantiate()
	(tag.get_node("Text") as Label).text = text
	_tags.add_child(tag)
	return tag
