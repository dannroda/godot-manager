extends AcceptDialog
## Agregar un plugin al proyecto: buscar en el Asset Store (`plugins search`),
## uno de los nuestros, o una fuente escrita a mano (github:owner/repo, una
## URL…). No instala: emite `add_requested` y el diálogo de detalles corre
## `plugins add`. `open_for(dir)` lo muestra para el proyecto de `dir`.

signal add_requested(source: String, pin: bool)

## Plugins nuestros, a un clic: {name, source, description}.
const FEATURED: Array[Dictionary] = [
	{"name": "Godot Agent", "source": "github:dannroda/godot-agent",
		"description": "Agentes de IA (Claude, Codex…) dentro del editor"},
	{"name": "Scope Compass", "source": "github:dannroda/scope-compass",
		"description": "Tablero de tareas del proyecto en el editor"},
]

var project_dir := ""
var page := 1
var pages := 0
var _query := ""
var _search_job: CliJob

@onready var _featured: HBoxContainer = %Featured
@onready var _query_edit: LineEdit = %Query
@onready var _search: Button = %SearchButton
@onready var _status: Label = %SearchStatus
@onready var _results: VBoxContainer = %Results
@onready var _more: Button = %More
@onready var _source: LineEdit = %Source
@onready var _add_source: Button = %AddSource
@onready var _pin: CheckBox = %Pin


func _ready() -> void:
	for f in FEATURED:
		var b := Button.new()
		b.text = tr("Agregar %s") % f.name
		b.tooltip_text = "%s\n%s" % [tr(f.description), f.source]
		b.pressed.connect(func() -> void: _request(f.source))
		_featured.add_child(b)
	_search.pressed.connect(func() -> void: search(_query_edit.text))
	_query_edit.text_submitted.connect(func(t: String) -> void: search(t))
	_more.pressed.connect(func() -> void: search(_query, page + 1))
	_source.text_changed.connect(func(t: String) -> void: _add_source.disabled = t.strip_edges().is_empty())
	_source.text_submitted.connect(func(t: String) -> void:
		if not t.strip_edges().is_empty():
			_request(t.strip_edges()))
	_add_source.pressed.connect(func() -> void: _request(_source.text.strip_edges()))
	_add_source.disabled = true


func open_for(dir: String) -> void:
	project_dir = dir
	_source.text = ""
	_add_source.disabled = true
	_pin.button_pressed = false
	if _results.get_child_count() == 0:
		_status.text = tr("Buscá por nombre: se muestran los que andan con el Godot del proyecto.")
	popup_centered_clamped(Vector2i(720, 600))
	_query_edit.grab_focus()


## Busca `query` (página `p`) y muestra los resultados; la página 1 reemplaza
## la lista, las siguientes se suman.
func search(query: String, p := 1) -> void:
	query = query.strip_edges()
	if query.is_empty() or project_dir.is_empty():
		return
	if _search_job != null and not _search_job.is_done():
		GmCli.cancel(_search_job)
	_query = query
	_status.text = tr("Buscando «%s»…") % query
	_search.disabled = true
	_more.visible = false
	if p == 1:
		show_results([])
	var job := GmCli.read(GmCommands.plugin_search(project_dir, query, p))
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
	show_results(r.value.assets, p > 1)


## Muestra `assets` (de StoreAsset); `append` los suma a los que hay.
func show_results(assets: Array, append := false) -> void:
	if not append:
		for child in _results.get_children():
			_results.remove_child(child)
			child.queue_free()
	for a: StoreAsset in assets:
		_results.add_child(_make_row(a))
	var total := _results.get_child_count()
	if total == 0:
		_status.text = tr("No hay resultados para «%s» que anden con este Godot.") % _query if not _query.is_empty() else ""
	else:
		_status.text = tr("Resultados para «%s»: %d") % [_query, total]
	_more.visible = page < pages and total > 0


func _make_row(a: StoreAsset) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"RowPanel"
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	box.add_child(info)
	var title := Label.new()
	title.name = "Title"
	title.text = a.name
	info.add_child(title)
	var meta := Label.new()
	meta.theme_type_variation = &"DimLabel"
	var bits: PackedStringArray = [a.publisher]
	if not a.license.is_empty():
		bits.append(a.license)
	bits.append(a.source)
	meta.text = " · ".join(bits)
	info.add_child(meta)
	if not a.description.is_empty():
		var desc := Label.new()
		desc.text = a.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size.x = 300
		info.add_child(desc)
	var add := Button.new()
	add.name = "Add"
	add.text = tr("Agregar")
	add.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add.pressed.connect(func() -> void: _request(a.source))
	box.add_child(add)
	return panel


func _request(source: String) -> void:
	hide()
	add_requested.emit(source, _pin.button_pressed)
