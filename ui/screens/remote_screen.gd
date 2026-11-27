extends PanelContainer
## Sección Descargar: los releases de GitHub (`list-remote`, una sola vez por
## sesión y después solo con Refrescar) cruzados con lo instalado (`list`, que
## es local y se vuelve a pedir cada vez que se muestra la pestaña). El canal y
## la búsqueda filtran en memoria, sin volver a pedir a GitHub.

signal selection_changed(release: RemoteVersion)
## Se confirmó una instalación; la corre el panel de progreso (main lo conecta).
signal install_requested(args: PackedStringArray, title: String)

const ROW_SCENE := preload("res://rows/remote_row.tscn")
const EDITION_MENU_NAME := &"EditionPickerMenu"

var releases: Array[RemoteVersion] = []
var installed: Array[InstalledVersion] = []
var selected: RemoteVersion

## Ya se pidió `list-remote` alguna vez (bien o mal).
var _loaded := false
var _loading_remote: CliJob
var _loading_installed: CliJob
var _marks := {}
var _load_error: CliError
## Escrituras de esta pantalla en curso (desinstalar).
var _busy := 0
## Con qué se llenó el formulario del panel: tag y lo instalado de esa versión.
var _form_key := ""

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
	%Install.pressed.connect(_on_install_pressed)
	%Uninstall.pressed.connect(_on_uninstall_pressed)
	%InstallForm.changed.connect(_update_actions)
	%DeleteDialog.delete_requested.connect(_write_and_refresh)
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
		&"gm_delete":
			var uninstall: Button = %Uninstall
			if not uninstall.visible or uninstall.disabled:
				return false
			uninstall.pressed.emit()
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
		_show_placeholder(tr("Cargando versiones de GitHub…"), ListState.Kind.LOADING)
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
	_update_actions()


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
		var text := tr("No se pudo traer la lista de GitHub:\n%s") % _load_error.message
		var hint := RemoteFilter.error_hint(_load_error)
		if not hint.is_empty():
			text += "\n\n" + hint
		_show_placeholder(text, ListState.Kind.ERROR, [["Reintentar", refresh]])
		_select(null)
		return
	if releases.is_empty():
		if _is_running(_loading_remote):
			_show_placeholder(tr("Cargando versiones de GitHub…"), ListState.Kind.LOADING)
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
		row.context_requested.connect(_on_row_context)
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


## Clic derecho en una fila: la selecciona y muestra sus acciones.
func _on_row_context(row: Control, at: Vector2) -> PopupMenu:
	_on_row_selected(row)
	return RowMenu.popup(self, [%Install, %ReleaseNotes, null, %Uninstall], at)


func _on_row_selected(row: Control) -> void:
	for r in _rows.get_children():
		r.is_selected = r == row
	_select(row.release)


## Doble clic o Enter: lleva al botón Instalar (no instala directo: las
## opciones están en el panel y una descarga se arranca a propósito).
func _on_row_activated(row: Control) -> void:
	_on_row_selected(row)
	var install: Button = %Install
	if not install.disabled:
		install.grab_focus()


func _select(rel: RemoteVersion) -> void:
	var changed := rel != selected
	selected = rel
	# Por tag y lo instalado: Refrescar o buscar no borran lo elegido, pero
	# después de instalar una edición el formulario pasa a la otra.
	var m: RemoteFilter.Marks = _marks.get(rel.tag) if rel != null else null
	var key := "" if rel == null else "%s|%s|%s" % [rel.tag, m != null and m.normal, m != null and m.mono]
	if key != _form_key:
		_form_key = key
		_fill_form()
	_update_actions()
	if changed:
		selection_changed.emit(rel)


## Versiones oficiales instaladas que corresponden a `rel` (normal antes que mono).
func _installed_for(rel: RemoteVersion) -> Array[InstalledVersion]:
	var out: Array[InstalledVersion] = []
	if rel == null:
		return out
	for v in installed:
		if not v.tag.is_empty() and v.tag == rel.tag:
			out.append(v)
	out.sort_custom(func(a: InstalledVersion, b: InstalledVersion) -> bool:
		if a.mono != b.mono:
			return not a.mono
		return a.name < b.name)
	return out


## Todas las ediciones disponibles de `rel` (normal, y mono si la trae) están instaladas.
func _all_editions_installed(rel: RemoteVersion) -> bool:
	if rel == null:
		return false
	var m: RemoteFilter.Marks = _marks.get(rel.tag)
	if m == null:
		return false
	return m.normal and (not rel.mono or m.mono)


## Llena las opciones del panel para la seleccionada. Si ya está la normal
## instalada (y la release trae Mono), arranca con Mono marcada.
func _fill_form() -> void:
	var form: InstallForm = %InstallForm
	if selected == null or not selected.editor:
		return
	var m: RemoteFilter.Marks = _marks.get(selected.tag)
	form.fill(selected, m != null and m.normal and not m.mono and selected.mono)


func _on_install_pressed() -> void:
	var form: InstallForm = %InstallForm
	if selected == null or not selected.editor or _all_editions_installed(selected) \
			or not form.problem().is_empty():
		return
	install_requested.emit(form.options.command(), InstallForm.title_for(form.options))


func _on_uninstall_pressed() -> void:
	if selected == null:
		return
	_pick_installed(%Uninstall, func(v: InstalledVersion) -> void: %DeleteDialog.open_for(v))


## Si hay una sola edición instalada del release seleccionado, corre `action`
## directo con ella; si están la normal y la mono, muestra un menú para elegir.
func _pick_installed(anchor: Control, action: Callable) -> PopupMenu:
	var matches := _installed_for(selected)
	if matches.is_empty():
		return null
	if matches.size() == 1:
		action.call(matches[0])
		return null
	var menu := get_node_or_null(NodePath(EDITION_MENU_NAME)) as PopupMenu
	if menu == null:
		menu = PopupMenu.new()
		menu.name = EDITION_MENU_NAME
		add_child(menu)
		menu.id_pressed.connect(func(id: int) -> void:
			var list: Array = menu.get_meta(&"versions", [])
			var cb: Callable = menu.get_meta(&"action", Callable())
			if id >= 0 and id < list.size() and cb.is_valid():
				cb.call(list[id]))
	menu.clear()
	menu.set_meta(&"versions", matches)
	menu.set_meta(&"action", action)
	for i in matches.size():
		menu.add_item(matches[i].name, i)
	menu.reset_size()
	var at := anchor.get_global_rect().position + Vector2(0.0, anchor.size.y)
	menu.popup(Rect2i(RowMenu.popup_position(self, menu, at), Vector2i.ZERO))
	return menu


## Corre una escritura (desinstalar); al terminar GmCli.versions_changed
## recarga lo instalado. Si falla, el aviso con el error del CLI lo muestra main.
func _write_and_refresh(args: PackedStringArray) -> CliJob:
	_busy += 1
	_update_actions()
	var job := GmCli.write(args)
	await job.finished
	_busy -= 1
	_update_actions()
	return job


## Actualiza las acciones según la selección y si la versión ya está instalada.
func _update_actions() -> void:
	%ReleaseNotes.disabled = selected == null
	var has_installed := selected != null and _marks.has(selected.tag)
	var all_installed := _all_editions_installed(selected)
	var install: Button = %Install
	var uninstall: Button = %Uninstall
	var form: InstallForm = %InstallForm
	var can_install := selected != null and selected.editor and not all_installed
	form.visible = can_install
	install.disabled = not can_install or not form.problem().is_empty()
	if selected != null and not selected.editor:
		install.tooltip_text = tr("godot-manager no instala el editor de esta versión en este sistema.")
	elif all_installed:
		install.tooltip_text = tr("Esta versión ya está instalada.")
	else:
		install.tooltip_text = ""
	uninstall.visible = has_installed
	uninstall.disabled = not has_installed or _busy > 0
	_update_inspector()


## El panel de la derecha: tag, fecha, tamaños y qué ya está instalado.
func _update_inspector() -> void:
	%Empty.visible = selected == null
	%Actions.visible = selected != null
	if selected == null:
		return
	%InspName.text = selected.tag
	var info := PackedStringArray()
	var day := RemoteFilter.day_of(selected.published_at)
	if not day.is_empty():
		info.append(tr("Publicada: %s") % day)
	if selected.editor_size > 0:
		info.append(tr("Editor: %s") % String.humanize_size(selected.editor_size))
	if selected.mono_size > 0:
		info.append(tr("Mono: %s") % String.humanize_size(selected.mono_size))
	if selected.templates_size > 0:
		info.append(tr("Export templates: %s") % String.humanize_size(selected.templates_size))
	if not selected.editor:
		info.append(tr("godot-manager no instala el editor de esta versión en este sistema."))
	%InspInfo.text = "\n".join(info)
	var installed_now := PackedStringArray()
	var m: RemoteFilter.Marks = _marks.get(selected.tag)
	if m != null and m.normal:
		installed_now.append(tr("Instalada"))
	if m != null and m.mono:
		installed_now.append(tr("Mono instalada"))
	%InspInstalled.text = " · ".join(installed_now)
	%InspInstalled.visible = not installed_now.is_empty()


static func _is_running(job: CliJob) -> bool:
	return job != null and not job.is_done()
