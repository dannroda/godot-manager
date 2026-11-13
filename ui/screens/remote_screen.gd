extends PanelContainer
## Pestaña Descargar: los releases de GitHub (`list-remote`, una sola vez por
## sesión y después solo con Refrescar) cruzados con lo instalado (`list`, que
## es local y se vuelve a pedir cada vez que se muestra la pestaña). El canal y
## la búsqueda filtran en memoria, sin volver a pedir a GitHub.

signal selection_changed(release: RemoteVersion)
## Se confirmó una instalación; la corre el panel de progreso (main lo conecta).
signal install_requested(args: PackedStringArray, title: String)

const ROW_SCENE := preload("res://rows/remote_row.tscn")

var releases: Array[RemoteVersion] = []
var installed: Array[InstalledVersion] = []
var selected: RemoteVersion

## Ya se pidió `list-remote` alguna vez (bien o mal).
var _loaded := false
var _loading_remote: CliJob
var _loading_installed: CliJob
var _marks := {}
var _load_error: CliError

@onready var _search: LineEdit = %Search
@onready var _channel: OptionButton = %Channel
@onready var _rows: VBoxContainer = %Rows
@onready var _placeholder: ListState = %Placeholder


func _ready() -> void:
	for ch: int in [RemoteFilter.Channel.STABLE, RemoteFilter.Channel.DEV, RemoteFilter.Channel.ALL]:
		_channel.add_item(RemoteFilter.CHANNEL_LABELS[ch], ch)
	_search.text_changed.connect(func(_t: String) -> void: _apply_filter())
	_search.text_submitted.connect(func(_t: String) -> void: focus_list())
	_channel.item_selected.connect(func(_i: int) -> void: _apply_filter())
	%Refresh.pressed.connect(refresh)
	%ReleaseNotes.pressed.connect(func() -> void:
		if selected != null:
			OS.shell_open(RemoteFilter.release_url(selected)))
	%Install.pressed.connect(func() -> void:
		if selected != null and selected.editor:
			%InstallDialog.open_install(selected))
	%InstallDialog.install_requested.connect(install_requested.emit)
	visibility_changed.connect(_on_shown)
	GmCli.versions_changed.connect(func() -> void:
		if is_visible_in_tree() and _loaded:
			refresh_installed())
	GmCli.availability_changed.connect(func(_ok: bool, _m: String) -> void: _on_shown())
	_update_actions()


func _on_shown() -> void:
	if not is_visible_in_tree() or not GmCli.available:
		return
	if not _loaded:
		refresh()
	else:
		refresh_installed()


## Atajos de main: Ctrl+F busca, F5 vuelve a pedir la lista a GitHub.
func handle_shortcut(action: StringName) -> bool:
	match action:
		&"gm_search":
			ListFocus.focus_search(_search)
		&"gm_refresh":
			refresh()
		_:
			return false
	return true


func focus_list() -> void:
	ListFocus.focus_rows(_rows, _search)


## Vuelve a pedir la lista a GitHub y lo instalado, en paralelo.
func refresh() -> void:
	if not GmCli.available or _is_running(_loading_remote):
		return
	_loaded = true
	_loading_remote = GmCli.read(GmCommands.list_remote())
	# Con una lista ya cargada, un error no la borra: lo avisa main.
	_loading_remote.notify_on_error = not releases.is_empty()
	if releases.is_empty():
		_show_placeholder("Cargando versiones de GitHub…", ListState.Kind.LOADING)
	refresh_installed()
	var job := _loading_remote
	await job.finished
	var r := GmParse.parse_remote(job.stdout) if job.succeeded() else null
	if r != null and r.ok:
		releases.assign(r.value)
		_load_error = null
	elif releases.is_empty():
		_load_error = GmParse.job_error(job) if r == null else r.error
	if _is_running(_loading_installed):
		await _loading_installed.finished
	_rebuild()


## Vuelve a pedir `list` (local) para actualizar las marcas de instalada.
func refresh_installed() -> void:
	if not GmCli.available or _is_running(_loading_installed):
		return
	_loading_installed = GmCli.read(GmCommands.list())
	_loading_installed.notify_on_error = false
	var job := _loading_installed
	await job.finished
	var r := GmParse.parse_list(job.stdout) if job.succeeded() else null
	if r != null and r.ok:
		installed.assign(r.value)
		_marks = RemoteFilter.installed_marks(installed)
	if not _is_running(_loading_remote):
		_rebuild()


## Las releases que se ven ahora, en orden.
func visible_releases() -> Array[RemoteVersion]:
	return RemoteFilter.apply(releases, _search.text, _channel.get_selected_id() as RemoteFilter.Channel)


## Vuelve a crear las filas (todas, en orden de versión); el filtro después
## solo las muestra u oculta, así buscar no recrea cientos de filas por tecla.
func _rebuild() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	if _load_error != null:
		var text := "No se pudo traer la lista de GitHub:\n" + _load_error.message
		var hint := RemoteFilter.error_hint(_load_error)
		if not hint.is_empty():
			text += "\n\n" + hint
		_show_placeholder(text, ListState.Kind.ERROR, [["Reintentar", refresh]])
		_select(null)
		return
	if releases.is_empty():
		if _is_running(_loading_remote):
			_show_placeholder("Cargando versiones de GitHub…", ListState.Kind.LOADING)
		else:
			_show_placeholder("GitHub no devolvió ninguna versión.", ListState.Kind.INFO,
				[["Reintentar", refresh]])
		_select(null)
		return
	for rel in RemoteFilter.apply(releases, "", RemoteFilter.Channel.ALL):
		var row := ROW_SCENE.instantiate()
		row.setup(rel, _marks.get(rel.tag))
		row.selected.connect(_on_row_selected)
		row.activated.connect(_on_row_activated)
		_rows.add_child(row)
	_apply_filter()


## Muestra las filas que pasan el canal y la búsqueda. Si la seleccionada
## queda oculta, se deselecciona.
func _apply_filter() -> void:
	if _rows.get_child_count() == 0:
		return
	var shown := {}
	for rel in visible_releases():
		shown[rel] = true
	var keep: RemoteVersion = null
	for row in _rows.get_children():
		row.visible = shown.has(row.release)
		# Por tag: después de Refrescar las releases son objetos nuevos.
		var is_it: bool = row.visible and selected != null and row.release.tag == selected.tag
		row.is_selected = is_it
		if is_it:
			keep = row.release
	if shown.is_empty():
		_show_placeholder("Ninguna versión coincide con la búsqueda.", ListState.Kind.INFO,
			[["Mostrar todas", _clear_filters]])
	else:
		_placeholder.visible = false
		_rows.get_parent().visible = true
	_select(keep)


func _show_placeholder(text: String, kind := ListState.Kind.INFO, actions: Array = []) -> void:
	_placeholder.show_state(text, kind, actions)
	_rows.get_parent().visible = false


## Vacía la búsqueda y pasa el canal a Todas.
func _clear_filters() -> void:
	_search.text = ""
	_channel.select(_channel.get_item_index(RemoteFilter.Channel.ALL))
	_apply_filter()


func _on_row_selected(row: Control) -> void:
	for r in _rows.get_children():
		r.is_selected = r == row
	_select(row.release)


func _on_row_activated(row: Control) -> void:
	_on_row_selected(row)
	var install: Button = %Install
	if not install.disabled:
		install.pressed.emit()


func _select(rel: RemoteVersion) -> void:
	var changed := rel != selected
	selected = rel
	_update_actions()
	if changed:
		selection_changed.emit(rel)


## Instalar solo si el CLI puede instalar el editor acá.
func _update_actions() -> void:
	%ReleaseNotes.disabled = selected == null
	%Install.disabled = selected == null or not selected.editor
	%Install.tooltip_text = "godot-manager no instala el editor de esta versión en este sistema." \
		if selected != null and not selected.editor else ""


static func _is_running(job: CliJob) -> bool:
	return job != null and not job.is_done()
