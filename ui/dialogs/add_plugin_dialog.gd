extends AcceptDialog
## Agregar un plugin al proyecto. Al abrirlo muestra sugeridos: los nuestros
## (de GitHub) y los mejor puntuados del Asset Store que andan con el Godot
## del proyecto (`plugins search` sin texto). Al buscar, los del Store que
## coinciden (y los nuestros, si coinciden). Cada tarjeta dice qué es: plugin
## de editor o recursos (arte, sonido…), estimado por las etiquetas del Store.
## También se puede escribir una fuente a mano (github:owner/repo, una URL…).
## No instala: emite `add_requested` y el diálogo de detalles corre
## `plugins add`. `open_for(dir)` lo muestra para el proyecto de `dir`.

signal add_requested(source: String, pin: bool)

## Los nuestros: van primero entre los sugeridos, como una tarjeta más.
const FEATURED: Array[Dictionary] = [
	{"name": "Godot Agent", "source": "github:dannroda/godot-agent", "publisher": "dannroda",
		"description": "Corre Claude Code, Codex y otros agentes de IA dentro del editor, con herramientas del editor por MCP.",
		"tags": ["IA", "Editor", "MCP"], "license": "MIT",
		"url": "https://github.com/dannroda/godot-agent", "thumbnail": ""},
	{"name": "Scope Compass", "source": "github:dannroda/scope-compass", "publisher": "dannroda",
		"description": "Tareas, hitos y playtests del proyecto en archivos JSON versionados con git, con un dock en el editor y una web local.",
		"tags": ["Productividad", "Editor"], "license": "MIT",
		"url": "https://github.com/dannroda/scope-compass",
		"thumbnail": "https://raw.githubusercontent.com/dannroda/scope-compass/main/web/favicon.svg"},
]

const THUMB_SIZE := Vector2(128, 72)

var project_dir := ""
var page := 1
var pages := 0
## Lo que se está mostrando: "" son los sugeridos.
var query := ""
var _search_job: CliJob

@onready var thumbnails: ThumbnailLoader = %Thumbnails
@onready var _query_edit: LineEdit = %Query
@onready var _search: Button = %SearchButton
@onready var _status: Label = %SearchStatus
@onready var _results: VBoxContainer = %Results
@onready var _more: Button = %More
@onready var _source: LineEdit = %Source
@onready var _add_source: Button = %AddSource
@onready var _pin: CheckBox = %Pin


func _ready() -> void:
	_search.pressed.connect(func() -> void: search(_query_edit.text))
	_query_edit.text_submitted.connect(func(t: String) -> void: search(t))
	# Al borrar la búsqueda, vuelven los sugeridos.
	_query_edit.text_changed.connect(func(t: String) -> void:
		if t.strip_edges().is_empty() and not query.is_empty():
			search(""))
	_more.pressed.connect(func() -> void: search(query, page + 1))
	_source.text_changed.connect(func(t: String) -> void: _add_source.disabled = t.strip_edges().is_empty())
	_source.text_submitted.connect(func(t: String) -> void:
		if not t.strip_edges().is_empty():
			_request(t.strip_edges()))
	_add_source.pressed.connect(func() -> void: _request(_source.text.strip_edges()))
	_add_source.disabled = true


func open_for(dir: String) -> void:
	var changed := dir != project_dir
	project_dir = dir
	_source.text = ""
	_add_source.disabled = true
	_pin.button_pressed = false
	popup_centered_clamped(Vector2i(860, 680))
	_query_edit.grab_focus()
	if changed or _results.get_child_count() == 0:
		_query_edit.text = ""
		search("")


## Los nuestros como StoreAsset; con `text`, solo los que coinciden.
static func featured(text := "") -> Array[StoreAsset]:
	var out: Array[StoreAsset] = []
	var q := text.strip_edges().to_lower()
	for f in FEATURED:
		var a := StoreAsset.new()
		a.featured = true
		a.source = f.source
		a.name = f.name
		a.publisher = f.publisher
		a.description = TranslationServer.translate(f.description)
		a.license = f.license
		a.page_url = f.url
		a.thumbnail = f.thumbnail
		a.kind = StoreAsset.Kind.PLUGIN
		for t: String in f.tags:
			a.tags.append(TranslationServer.translate(t))
		var haystack := " ".join([a.name, a.description, a.source, " ".join(a.tags)]).to_lower()
		if q.is_empty() or haystack.contains(q):
			out.append(a)
	return out


## Busca `text` en el Store (página `p`); sin texto, los sugeridos. La página 1
## reemplaza la lista (con los nuestros que coinciden arriba), las siguientes
## se suman.
func search(text: String, p := 1) -> void:
	text = text.strip_edges()
	if project_dir.is_empty():
		return
	if _search_job != null and not _search_job.is_done():
		GmCli.cancel(_search_job)
	query = text
	_more.visible = false
	if p == 1:
		show_results(featured(text))
	_status.text = tr("Buscando «%s»…") % text if not text.is_empty() else tr("Buscando los más populares del Asset Store…")
	if not GmCli.available:
		_status.text = tr("No se encontró godot-manager: solo se muestran los nuestros.")
		return
	_search.disabled = true
	var job := GmCli.read(GmCommands.plugin_search(project_dir, text, p))
	job.notify_on_error = false
	_search_job = job
	await job.finished
	if job != _search_job or job.cancelled:
		return
	_search.disabled = false
	var r := GmParse.parse_plugin_search(job.stdout) if job.start_error == null else null
	if r == null or not r.ok:
		var err := r.error if r != null else GmParse.job_error(job)
		_status.text = err.message if err != null else tr("La búsqueda falló.")
		return
	page = p
	pages = r.value.pages
	show_results(r.value.assets, true)


## Muestra `assets` (de StoreAsset); `append` los suma a los que hay.
func show_results(assets: Array, append := false) -> void:
	if not append:
		for child in _results.get_children():
			_results.remove_child(child)
			child.queue_free()
	for a: StoreAsset in assets:
		_results.add_child(make_card(a))
	var store := 0
	for child in _results.get_children():
		if not child.get_meta(&"featured", false):
			store += 1
	if query.is_empty():
		_status.text = tr("Sugeridos: los nuestros y los mejor puntuados del Asset Store que andan con el Godot del proyecto.")
	elif _results.get_child_count() == 0:
		_status.text = tr("No hay resultados para «%s» que anden con este Godot.") % query
	else:
		_status.text = tr("Resultados para «%s»: %d") % [query, _results.get_child_count()]
	_more.visible = page < pages and store > 0


## La tarjeta de un asset: miniatura, nombre con qué es, autor y licencia,
## descripción, etiquetas y los botones.
func make_card(a: StoreAsset) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"RowPanel"
	panel.set_meta(&"featured", a.featured)
	panel.set_meta(&"source", a.source)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(_thumbnail(a))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	box.add_child(info)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	info.add_child(head)
	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = &"TitleLabel"
	title.text = a.name
	head.add_child(title)
	var kind := kind_text(a.kind)
	if not kind.is_empty():
		head.add_child(_badge("Kind", kind, kind_tooltip(a)))
	if a.featured:
		head.add_child(_badge("Featured", tr("Sugerido"), tr("De los autores de godot-manager")))

	var meta := Label.new()
	meta.name = "Meta"
	meta.theme_type_variation = &"DimLabel"
	var bits: PackedStringArray = []
	if not a.publisher.is_empty():
		bits.append(a.publisher)
	if not a.license.is_empty():
		bits.append(a.license)
	if a.score > 0:
		bits.append(tr("reseñas: %d%%") % a.score)
	bits.append(tr("GitHub") if a.source.begins_with("github:") else tr("Asset Store"))
	meta.text = " · ".join(bits)
	meta.tooltip_text = a.source
	meta.mouse_filter = Control.MOUSE_FILTER_PASS
	info.add_child(meta)
	if not a.description.is_empty():
		var desc := Label.new()
		desc.name = "Description"
		desc.text = a.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.max_lines_visible = 3
		desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		desc.custom_minimum_size.x = 320
		desc.tooltip_text = a.description
		desc.mouse_filter = Control.MOUSE_FILTER_PASS
		info.add_child(desc)
	if not a.tags.is_empty():
		var tags := Label.new()
		tags.name = "Tags"
		tags.theme_type_variation = &"DimLabel"
		tags.text = " · ".join(a.tags)
		tags.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		info.add_child(tags)

	var actions := VBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(actions)
	var add := Button.new()
	add.name = "Add"
	add.text = tr("Agregar")
	add.theme_type_variation = &"AccentButton"
	add.tooltip_text = tr("Lo instala en el proyecto (%s)") % a.source
	add.pressed.connect(func() -> void: _request(a.source))
	actions.add_child(add)
	if not a.page_url.is_empty():
		var view := Button.new()
		view.name = "View"
		view.text = tr("Ver en GitHub") if a.source.begins_with("github:") else tr("Ver en el Store")
		view.tooltip_text = a.page_url
		view.pressed.connect(func() -> void: OS.shell_open(a.page_url))
		actions.add_child(view)
	return panel


static func kind_text(kind: StoreAsset.Kind) -> String:
	match kind:
		StoreAsset.Kind.PLUGIN:
			return TranslationServer.translate("Plugin")
		StoreAsset.Kind.CONTENT:
			return TranslationServer.translate("Recursos")
	return ""


static func kind_tooltip(a: StoreAsset) -> String:
	if a.featured:
		return TranslationServer.translate("Plugin de editor: se activa en el proyecto.")
	if a.kind == StoreAsset.Kind.PLUGIN:
		return TranslationServer.translate("Trae código (un plugin, una librería o una herramienta del editor), según sus etiquetas del Store. Al instalarlo se ve si tiene un plugin de editor para activar.")
	return TranslationServer.translate("Arte, sonido u otros archivos para el proyecto, según sus etiquetas del Store. Al instalarlo se ve si trae algo para activar.")


## La miniatura, con las iniciales de fondo hasta que llega la imagen (o si no tiene).
func _thumbnail(a: StoreAsset) -> Control:
	var frame := PanelContainer.new()
	frame.name = "Thumbnail"
	frame.theme_type_variation = &"Tag"
	frame.custom_minimum_size = THUMB_SIZE
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.clip_contents = true
	var initials := Label.new()
	initials.name = "Initials"
	initials.text = initials_of(a.name)
	initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initials.add_theme_font_size_override("font_size", 26)
	initials.add_theme_color_override("font_color", Color.from_hsv(float(absi(hash(a.source)) % 360) / 360.0, 0.45, 0.95))
	frame.add_child(initials)
	var image := TextureRect.new()
	image.name = "Image"
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = THUMB_SIZE
	frame.add_child(image)
	if thumbnails != null:
		thumbnails.load_into(a.thumbnail, image)
	return frame


## Hasta dos iniciales del nombre ("Phantom Camera" → "PC", "@icons" → "I").
static func initials_of(name: String) -> String:
	var out := ""
	for word in name.split(" ", false):
		for c in word:
			if c.to_upper() != c.to_lower() or c.is_valid_int():
				out += c.to_upper()
				break
		if out.length() == 2:
			break
	return out if not out.is_empty() else "?"


func _badge(node_name: String, text: String, tooltip: String) -> Control:
	var badge := PanelContainer.new()
	badge.name = node_name
	badge.theme_type_variation = &"Tag"
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.tooltip_text = tooltip
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	badge.add_child(label)
	return badge


func _request(source: String) -> void:
	hide()
	add_requested.emit(source, _pin.button_pressed)
