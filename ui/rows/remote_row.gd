extends SelectableRow
## Fila de una versión remota: tag, Dev, lo que ya está instalado de ella,
## fecha de publicación y tamaño del editor. Si el CLI no puede instalar el
## editor en esta plataforma (`editor: false`, las 3.x en Linux), va atenuada.

const TAG_SCENE := preload("res://rows/tag.tscn")

var release: RemoteVersion
var marks: RemoteFilter.Marks

@onready var _name: Label = %Name
@onready var _tags: HBoxContainer = %Tags
@onready var _date: Label = %Date
@onready var _size: Label = %Size


func _ready() -> void:
	super()
	if release != null:
		_fill()


func setup(r: RemoteVersion, m: RemoteFilter.Marks) -> void:
	release = r
	marks = m
	if is_node_ready():
		_fill()


func _fill() -> void:
	_name.text = release.tag
	_date.text = RemoteFilter.day_of(release.published_at)
	_size.text = String.humanize_size(release.editor_size) if release.editor_size > 0 else ""
	for child in _tags.get_children():
		child.queue_free()
	if release.prerelease:
		_add_tag(tr("Dev"))
	if marks != null and marks.normal:
		_add_tag(tr("Instalada"))
	if marks != null and marks.mono:
		_add_tag(tr("Mono instalada"))
	modulate.a = 1.0 if release.editor else 0.5
	tooltip_text = "" if release.editor else tr("godot-manager no instala el editor de esta versión en este sistema.")


func _add_tag(text: String) -> void:
	var tag := TAG_SCENE.instantiate()
	(tag.get_node("Text") as Label).text = text
	_tags.add_child(tag)
