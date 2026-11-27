extends PanelContainer
## Sección Versiones: las versiones instaladas (`list`), con búsqueda, filtro y
## las acciones de la seleccionada. Recarga al mostrarse y con Refrescar; la
## búsqueda y el filtro trabajan sobre lo ya cargado.

signal selection_changed(version: InstalledVersion)
## Templates o símbolos para la seleccionada; los corre el panel de progreso
## (main lo conecta).
signal install_requested(args: PackedStringArray, title: String)
## Pide ir a otra pestaña (&"remote", &"projects"…); main la cambia.
signal tab_requested(tab: StringName)
## La default y cuántas tienen una versión nueva sin instalar (barra lateral).
signal summary_changed(default_name: String, updates: int)

const ROW_SCENE := preload("res://rows/version_row.tscn")

var versions: Array[InstalledVersion] = []
var selected: InstalledVersion

var _loading: CliJob
var _load_error := ""
## Nombre de versión → VersionUpdate, de `outdated`.
var _updates := {}
## Las versiones para las que se pidió `outdated` (consulta GitHub: se repite
## solo si cambia lo instalado).
var _updates_for := ""
var _checking_updates: CliJob
## Escrituras de esta pantalla en curso.
var _busy := 0

@onready var _search: LineEdit = %Search
@onready var _filter: OptionButton = %Filter
@onready var _rows: VBoxContainer = %Rows
@onready var _placeholder: ListState = %Placeholder


func _ready() -> void:
	for kind: int in VersionFilter.KIND_LABELS:
		_filter.add_item(VersionFilter.KIND_LABELS[kind], kind)
	_search.text_changed.connect(func(_t: String) -> void: _rebuild())
	# Enter en la búsqueda baja a la lista.
	_search.text_submitted.connect(func(_t: String) -> void: focus_list())
	_filter.item_selected.connect(func(_i: int) -> void: _rebuild())
	%Refresh.pressed.connect(refresh)
	%SetDefault.pressed.connect(_set_default)
	%Launch.pressed.connect(_launch)
	# Abre el administrador de archivos con el ejecutable seleccionado.
	%ShowFolder.pressed.connect(func() -> void:
		if selected != null and not selected.path.is_empty():
			OS.shell_show_in_file_manager(selected.path))
	%Delete.pressed.connect(func() -> void:
		if selected != null:
			%DeleteDialog.open_for(selected))
	%DeleteDialog.delete_requested.connect(_write_and_refresh)
	%AddBuild.pressed.connect(func() -> void:
		var names := PackedStringArray()
		for v in versions:
			names.append(v.name)
		%AddBuildDialog.open_with(names))
	%AddBuildDialog.add_requested.connect(_write_and_refresh)
	%Templates.pressed.connect(func() -> void:
		if selected != null and not selected.custom:
			%TemplatesDialog.open_templates(selected))
	%TemplatesDialog.install_requested.connect(install_requested.emit)
	%Upgrade.pressed.connect(_upgrade)
	%Prune.pressed.connect(func() -> void:
		%PruneDialog.open_with(ProjectList.load_from().paths))
	%PruneDialog.prune_requested.connect(_write_and_refresh)
	%Symbols.pressed.connect(func() -> void:
		if selected != null and not selected.custom and not selected.debug_symbols:
			install_requested.emit(GmCommands.symbols(selected.name), tr("Instalando símbolos de %s") % selected.name))
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			refresh())
	GmCli.availability_changed.connect(func(ok: bool, _m: String) -> void:
		if ok and is_visible_in_tree():
			refresh())
	# Oculta no hace falta: al mostrarse vuelve a pedir la lista.
	GmCli.versions_changed.connect(func() -> void:
		if is_visible_in_tree():
			refresh())
	_update_actions()


## Atajos de main: Ctrl+F busca, F5 refresca, Supr pide borrar la seleccionada.
func handle_shortcut(action: StringName) -> bool:
	match action:
		&"gm_search":
			ListFocus.focus_search(_search)
		&"gm_refresh":
			refresh()
		&"gm_delete":
			if (%Delete as Button).disabled:
				return false
			%Delete.pressed.emit()
		_:
			return false
	return true


func focus_list() -> void:
	ListFocus.focus_rows(_rows, _search)


## Vuelve a pedir `list` (si el CLI está disponible y no hay uno en curso).
func refresh() -> void:
	if not GmCli.available or (_loading != null and not _loading.is_done()):
		return
	_loading = GmCli.read(GmCommands.list())
	_loading.notify_on_error = false
	if versions.is_empty():
		_show_placeholder(tr("Cargando versiones…"), ListState.Kind.LOADING)
	await _loading.finished
	var job := _loading
	var r := GmParse.parse_list(job.stdout) if job.succeeded() else null
	if r != null and r.ok:
		versions.assign(r.value)
		_load_error = ""
		check_updates()
	else:
		var err := GmParse.job_error(job) if r == null else r.error
		_load_error = err.message if err != null else tr("No se pudo leer la lista.")
	_rebuild()


## Pide `outdated` en segundo plano si cambió lo instalado desde la última
## vez. Sin red o con el límite de GitHub no pasa nada: no se marca ninguna.
func check_updates() -> void:
	var names := PackedStringArray()
	for v in versions:
		names.append(v.name)
	var key := ",".join(names)
	if key == _updates_for or (_checking_updates != null and not _checking_updates.is_done()):
		return
	_updates_for = key
	_checking_updates = GmCli.read_background(GmCommands.outdated())
	var job := _checking_updates
	await job.finished
	var r := GmParse.parse_outdated(job.stdout) if job.succeeded() else null
	if r == null or not r.ok:
		_updates_for = ""  # que lo vuelva a intentar en el próximo refresh
		return
	_updates.clear()
	for u: VersionUpdate in r.value:
		_updates[u.version] = u
	_rebuild()


func _emit_summary() -> void:
	var default_name := ""
	var updates := 0
	for v in versions:
		if v.is_default:
			default_name = v.name
		var u := update_for(v)
		if u != null and not u.installed:
			updates += 1
	summary_changed.emit(default_name, updates)


## La actualización disponible para `v` (null si no hay).
func update_for(v: InstalledVersion) -> VersionUpdate:
	return _updates.get(v.name) if v != null else null


## Las versiones que se ven ahora, en orden.
func visible_versions() -> Array[InstalledVersion]:
	return VersionFilter.apply(versions, _search.text, _filter.get_selected_id() as VersionFilter.Kind)


func _rebuild() -> void:
	# Si el foco estaba en una fila, vuelve a la lista después de recrearla.
	var focus := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var had_focus := focus != null and _rows.is_ancestor_of(focus)
	if had_focus:
		focus.release_focus()
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	if not _load_error.is_empty():
		summary_changed.emit("", 0)
		_show_placeholder(tr("No se pudo cargar la lista:\n%s") % _load_error, ListState.Kind.ERROR,
			[[tr("Reintentar"), refresh]])
		_select(null)
		return
	_emit_summary()
	var shown := visible_versions()
	var keep: InstalledVersion = null
	var groups := VersionFilter.group_by_series(shown)
	for g: Array in groups:
		# Con una sola serie el título no agrega nada.
		if groups.size() > 1:
			_rows.add_child(_group_title(g[0]))
		for v: InstalledVersion in g[1]:
			var row := ROW_SCENE.instantiate()
			row.setup(v, update_for(v))
			row.selected.connect(_on_row_selected)
			row.activated.connect(_on_row_activated)
			row.context_requested.connect(_on_row_context)
			_rows.add_child(row)
			if selected != null and v.name == selected.name:
				keep = v
				row.is_selected = true
	if shown.is_empty() and versions.is_empty():
		_show_placeholder(tr("No hay versiones instaladas."), ListState.Kind.INFO, [
			["Ir a Descargar", func() -> void: tab_requested.emit(&"remote")],
			[tr("Agregar build propio"), func() -> void: %AddBuild.pressed.emit()]])
	elif shown.is_empty():
		_show_placeholder(tr("Ninguna versión coincide con la búsqueda."), ListState.Kind.INFO,
			[[tr("Mostrar todas"), _clear_filters]])
	else:
		_placeholder.visible = false
		_rows.get_parent().visible = true
	_select(keep)
	if had_focus:
		focus_list.call_deferred()


## Título de un grupo de la lista: "4.8", o "Builds propios".
func _group_title(series: String) -> Label:
	var title := Label.new()
	title.text = series if not series.is_empty() else tr("Builds propios")
	title.theme_type_variation = &"GroupTitle"
	return title


func _show_placeholder(text: String, kind := ListState.Kind.INFO, actions: Array = []) -> void:
	_placeholder.show_state(text, kind, actions)
	_rows.get_parent().visible = false


## Vacía la búsqueda y vuelve el filtro a Todas.
func _clear_filters() -> void:
	_search.text = ""
	_filter.select(_filter.get_item_index(VersionFilter.Kind.ALL))
	_rebuild()


## Clic derecho en una fila: la selecciona y muestra sus acciones.
func _on_row_context(row: Control, at: Vector2) -> PopupMenu:
	_on_row_selected(row)
	return RowMenu.popup(self, [%Launch, %SetDefault, %Upgrade, null, %Templates, %Symbols, %ShowFolder, null, %Delete], at)


func _on_row_selected(row: Control) -> void:
	for r in _rows.get_children():
		if r is SelectableRow:
			r.is_selected = r == row
	_select(row.version)


func _on_row_activated(row: Control) -> void:
	_on_row_selected(row)
	var launch: Button = %Launch
	if not launch.disabled:
		launch.pressed.emit()


func _select(v: InstalledVersion) -> void:
	var changed := v != selected
	selected = v
	_update_actions()
	if changed:
		selection_changed.emit(v)


## Corre una escritura; al terminar (bien o mal) la lista se recarga con
## GmCli.versions_changed. Si falla, el aviso con el error del CLI lo muestra main.
func _write_and_refresh(args: PackedStringArray) -> CliJob:
	_busy += 1
	_update_actions()
	var job := GmCli.write(args)
	await job.finished
	_busy -= 1
	_update_actions()
	return job


func _set_default() -> void:
	if selected == null or selected.is_default:
		return
	await _write_and_refresh(GmCommands.set_default(selected.name))


## Instala la más nueva de la serie de la seleccionada en el panel de
## progreso (si era la default, la nueva pasa a serlo).
func _upgrade() -> void:
	var u := update_for(selected)
	if u == null or u.installed:
		return
	install_requested.emit(GmCommands.upgrade(selected.name),
		tr("Actualizando %s a %s") % [selected.name, u.latest])


## Abre el Project Manager de la versión seleccionada con `launch --detach`:
## el CLI responde apenas arranca el proceso, así que la UI no queda esperando
## a que se cierre el editor. Si no arranca, main muestra el error del CLI.
func _launch() -> CliJob:
	if selected == null:
		return null
	var job := GmCli.read(GmCommands.launch(selected.name, PackedStringArray(["--project-manager"])))
	await job.finished
	return job


## Habilita las acciones según la selección (las conectan 1.2–1.5). Mientras
## corre una escritura de esta pantalla, las que escriben quedan apagadas.
func _update_actions() -> void:
	var none := selected == null
	for button: Button in [%Launch, %SetDefault, %Templates, %Symbols, %ShowFolder, %Delete]:
		button.disabled = none
	if not none and selected.is_default:
		%SetDefault.disabled = true
	# Templates y símbolos oficiales: no para builds propios.
	if not none and selected.custom:
		%Templates.disabled = true
		%Symbols.disabled = true
	if not none and selected.debug_symbols:
		%Symbols.disabled = true
	%Symbols.tooltip_text = tr("Esta versión ya tiene los símbolos de debug.") \
		if not none and selected.debug_symbols else tr("Agrega los símbolos de debug del editor de esta versión")
	var u := update_for(selected)
	_update_inspector(u)
	var upgrade: Button = %Upgrade
	upgrade.visible = u != null
	upgrade.disabled = u == null or u.installed
	if u != null:
		upgrade.text = tr("Actualizar a %s") % u.latest
		upgrade.tooltip_text = tr("%s ya está instalada.") % u.latest if u.installed \
			else tr("Instala %s con lo mismo que tiene esta (mono, export templates, símbolos). Esta queda instalada.") % u.latest
	if _busy > 0:
		for button: Button in [%SetDefault, %Delete, %AddBuild, %Prune]:
			button.disabled = true
	else:
		%AddBuild.disabled = false
		%Prune.disabled = false


## El panel de la derecha: nombre, carpeta y qué tiene la seleccionada.
func _update_inspector(u: VersionUpdate) -> void:
	%Empty.visible = selected == null
	%Actions.visible = selected != null
	if selected == null:
		return
	%InspName.text = selected.name
	%InspPath.text = selected.path
	var info := PackedStringArray()
	if selected.is_default:
		info.append(tr("Versión por defecto"))
	if selected.mono:
		info.append(tr("Mono"))
	if selected.custom:
		info.append(tr("Build propio"))
	if selected.debug_symbols:
		info.append(tr("Símbolos"))
	if not selected.template_platforms.is_empty():
		info.append(tr("Templates: %s") % ", ".join(selected.template_platforms))
	if u != null and not u.installed:
		info.append(tr("Nueva: %s") % u.latest)
	%InspInfo.text = " · ".join(info)
	%InspInfo.visible = not info.is_empty()
