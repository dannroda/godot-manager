extends PanelContainer
## Sección Proyectos: la lista propia de proyectos (`user://projects.cfg`),
## con agregar, escanear una carpeta (en un Thread, para no trabar la UI) y
## quitar de la lista (no borra nada). Búsqueda y orden sobre lo cargado.

signal selection_changed(project: ProjectEntry)
## Instalar la versión que fija un proyecto; lo corre el panel de progreso
## (main lo conecta).
signal install_requested(args: PackedStringArray, title: String)
## Un error del CLI para el aviso de main (el mensaje tal cual).
signal error_reported(message: String)
## Una escritura larga ya lanzada (crear un proyecto) para el panel de progreso.
signal job_started(job: CliJob, title: String)

const ROW_SCENE := preload("res://rows/project_row.tscn")
const MissingVersionDialog := preload("res://dialogs/missing_version_dialog.gd")
const ERROR_COLOR := preload("res://rows/project_row.gd").ERROR_COLOR
## Cuántos `which` corren a la vez.
const WHICH_PARALLEL := 4

## Dónde se guarda la lista (los tests usan otra).
var list_path := ProjectList.PATH
var list: ProjectList
var entries: Array[ProjectEntry] = []
var selected: ProjectEntry

## Ruta → ProjectStatus (la versión que usa cada proyecto, 3.2).
var statuses := {}

var _scan_thread: Thread
## Rutas que esperan su `which`, y cuántos corren ahora.
var _which_pending: PackedStringArray = []
var _which_running := 0
## Abrir (o correr) un proyecto después de cambiarle la versión, si el cambio
## vino de un Abrir/Correr con la versión sin instalar: {path, edit}.
var _open_after := {}
## Para el diálogo de versión no instalada: el proyecto, las instaladas, la
## default y la más nueva instalada del mismo minor.
var _missing_for: ProjectEntry
var _missing_installed: Array[InstalledVersion] = []
var _missing_default := ""
var _missing_suggested := ""

@onready var _search: LineEdit = %Search
@onready var _sort: OptionButton = %Sort
@onready var _rows: VBoxContainer = %Rows
@onready var _placeholder: ListState = %Placeholder
@onready var _status: Label = %Status
@onready var _add_dialog: FileDialog = %AddDialog
@onready var _scan_dialog: FileDialog = %ScanDialog
@onready var _remove_dialog: ConfirmationDialog = %RemoveDialog
@onready var _message: AcceptDialog = %MessageDialog


func _ready() -> void:
	for s: int in ProjectList.SORT_LABELS:
		_sort.add_item(ProjectList.SORT_LABELS[s], s)
	_search.text_changed.connect(func(_t: String) -> void: _rebuild())
	_search.text_submitted.connect(func(_t: String) -> void: focus_list())
	_sort.item_selected.connect(func(_i: int) -> void:
		list.sort = _sort.get_selected_id() as ProjectList.Sort
		_save()
		_rebuild())
	%NewProject.pressed.connect(func() -> void:
		var base := selected.path.get_base_dir() if selected != null else list.last_scan_dir
		%NewProjectDialog.open_with(_start_dir(base)))
	%NewProjectDialog.create_requested.connect(create_project)
	%Add.pressed.connect(func() -> void:
		_add_dialog.current_dir = _start_dir(selected.path.get_base_dir() if selected != null else "")
		_add_dialog.popup_centered_clamped(Vector2i(760, 480)))
	_add_dialog.dir_selected.connect(add_project)
	%Scan.pressed.connect(func() -> void:
		_scan_dialog.current_dir = _start_dir(list.last_scan_dir)
		_scan_dialog.popup_centered_clamped(Vector2i(760, 480)))
	_scan_dialog.dir_selected.connect(func(dir: String) -> void: scan_folder(dir))
	%Remove.pressed.connect(func() -> void:
		if selected == null:
			return
		_remove_dialog.dialog_text = tr("¿Quitar «%s» de la lista?\n%s\n\nNo se borra nada del disco.") % [
			selected.name, selected.path]
		_remove_dialog.reset_size()
		_remove_dialog.popup_centered()
		_remove_dialog.get_cancel_button().grab_focus())
	_remove_dialog.confirmed.connect(func() -> void:
		if selected != null:
			remove_project(selected.path))
	%ShowFolder.pressed.connect(func() -> void:
		if selected != null and not selected.missing:
			OS.shell_show_in_file_manager(selected.path.path_join(ProjectEntry.PROJECT_FILE)))
	%Open.pressed.connect(func() -> void: open_selected(true))
	%Run.pressed.connect(func() -> void: open_selected(false))
	%ImportPM.pressed.connect(func() -> void: import_from_pm(ProjectList.pm_config_path()))
	%ChangeVersion.pressed.connect(open_change_version)
	%Details.pressed.connect(open_details)
	%ChangeVersionDialog.change_requested.connect(change_version)
	%ChangeVersionDialog.canceled.connect(func() -> void: _open_after = {})
	%MissingVersionDialog.choice.connect(_on_missing_choice)
	%InstallDialog.install_requested.connect(install_requested.emit)
	# Una instalación, un borrado o cambiar la default cambian lo que resuelve
	# cada proyecto; también cuando el CLI vuelve a estar disponible.
	GmCli.versions_changed.connect(func() -> void: resolve_versions())
	GmCli.availability_changed.connect(func(ok: bool, _m: String) -> void:
		if ok:
			resolve_versions())
	load_list()


func _exit_tree() -> void:
	if _scan_thread != null and _scan_thread.is_started():
		_scan_thread.wait_to_finish()


## Atajos de main: Ctrl+F busca, F5 vuelve a leer los proyectos y sus
## versiones, Supr pide quitar el seleccionado de la lista.
func handle_shortcut(action: StringName) -> bool:
	match action:
		&"gm_search":
			ListFocus.focus_search(_search)
		&"gm_refresh":
			refresh()
		&"gm_delete":
			if (%Remove as Button).disabled:
				return false
			%Remove.pressed.emit()
		_:
			return false
	return true


func focus_list() -> void:
	ListFocus.focus_rows(_rows, _search)


## Vuelve a leer el project.godot de cada uno (nombre, ícono, fecha) y a
## preguntar sus versiones, sin perder la selección.
func refresh() -> void:
	for i in entries.size():
		entries[i] = ProjectEntry.read(entries[i].path)
	if selected != null:
		selected = _entry(selected.path)
	_rebuild()
	resolve_versions()


## Carga la lista guardada y lee el project.godot de cada una.
func load_list() -> void:
	list = ProjectList.load_from(list_path)
	_sort.select(_sort.get_item_index(list.sort))
	entries.clear()
	for p in list.paths:
		entries.append(ProjectEntry.read(p))
	statuses.clear()
	_rebuild()
	resolve_versions()


## Pide `--dir <p> which` para esas rutas (vacío: todas), de a WHICH_PARALLEL.
## Lo que ya estaba mostrado queda hasta que llega la respuesta nueva.
func resolve_versions(paths: PackedStringArray = []) -> void:
	if not GmCli.available:
		return
	if paths.is_empty():
		for e in entries:
			paths.append(e.path)
	for p in paths:
		var e := _entry(p)
		if e == null or e.missing or p in _which_pending:
			continue
		_which_pending.append(p)
		if not statuses.has(p):
			statuses[p] = ProjectStatus.pending()
			_update_row(p)
	while _which_running < WHICH_PARALLEL and not _which_pending.is_empty():
		_which_worker()


## Hay `which` en curso o esperando.
func is_resolving() -> bool:
	return _which_running > 0 or not _which_pending.is_empty()


func _which_worker() -> void:
	_which_running += 1
	while not _which_pending.is_empty():
		var p := _which_pending[0]
		_which_pending.remove_at(0)
		var job := GmCli.read_background(GmCommands.which(p))
		await job.finished
		# Si lo quitaron de la lista mientras tanto, se descarta.
		if _entry(p) != null:
			statuses[p] = ProjectStatus.from_job(job)
			_update_row(p)
	_which_running -= 1


func _update_row(path: String) -> void:
	for row in _rows.get_children():
		if row.project.path == path:
			row.set_status(statuses.get(path))
	if selected != null and selected.path == path:
		_update_inspector()


func _entry(path: String) -> ProjectEntry:
	for e in entries:
		if e.path == path:
			return e
	return null


## Abre el seleccionado en el editor (`edit`) o lo corre, con
## `--dir <p> run --detach [-e]`: el CLI resuelve la versión en ese momento y
## vuelve enseguida. Si la versión fijada no está instalada, ofrece instalarla;
## otros errores van al aviso de main con el mensaje del CLI.
func open_selected(edit := true) -> CliJob:
	if selected == null or selected.missing:
		return null
	var e := selected
	var job := GmCli.read(GmCommands.open_project(e.path) if edit else GmCommands.run_project(e.path))
	job.notify_on_error = false
	_set_status((tr("Abriendo «%s»…") if edit else tr("Corriendo «%s»…")) % e.name)
	await job.finished
	if job.succeeded():
		var ok := GmParse.parse_ok(job.stdout)
		var version := str((ok.value as Dictionary).get("version", "")) if ok.ok else ""
		_set_status((tr("Se abrió «%s» con %s.") if edit else tr("Se corrió «%s» con %s.")) % [e.name, version])
		return job
	var err := GmParse.job_error(job)
	var message := err.message if err != null else tr("godot-manager terminó con código %d") % job.exit_code
	if err != null and err.code == "not_installed":
		# Es la misma respuesta que da which: la fila se actualiza con esto.
		statuses[e.path] = ProjectStatus.from_job(job)
		_update_row(e.path)
		_set_status(tr("«%s» usa %s, que no está instalada.") % [e.name, statuses[e.path].missing_version()])
		ask_missing(e, 1 if edit else 0)
		return job
	_set_status(tr("No se pudo abrir «%s».") % e.name)
	error_reported.emit(message)
	return job


## Pide `list` y abre el selector de versión para el seleccionado.
func open_change_version() -> void:
	if selected == null or selected.missing:
		return
	var e := selected
	%ChangeVersion.disabled = true
	var job := GmCli.read(GmCommands.list())
	await job.finished
	_update_actions()
	var r := GmParse.parse_list(job.stdout) if job.succeeded() else null
	if r == null or not r.ok:
		var err := GmParse.job_error(job) if r == null else r.error
		# Si falló el proceso, main ya avisó; si no se pudo leer, avisa esto.
		if r != null:
			error_reported.emit(err.message)
		return
	var installed: Array[InstalledVersion] = []
	installed.assign(r.value)
	%ChangeVersionDialog.open_for(e, installed, statuses.get(e.path))


## Detalles del seleccionado, con sus plugins.
func open_details() -> void:
	if selected == null or selected.missing:
		return
	%ProjectDetailsDialog.open_for(selected, statuses.get(selected.path))


## Corre `set-local` / `set-local --unset` por la cola de escrituras; al
## terminar, versions_changed vuelve a pedir el which de todos (y el de este).
func change_version(args: PackedStringArray) -> CliJob:
	var job := GmCli.write(args)
	await job.finished
	var path := args[2] if args.size() > 2 else ""
	if job.succeeded():
		var project := _entry(path)
		_set_status(tr("Listo: «%s» %s.") % [project.name if project != null else path,
			tr("usa la default") if args.has("--unset") else tr("usa %s") % args[-1]])
		if not _open_after.is_empty() and _open_after["path"] == path and project != null:
			var edit: bool = _open_after["edit"]
			_open_after = {}
			selected = project
			_update_actions()
			open_selected(edit)
	else:
		_open_after = {}
	return job


## La versión que pide `e` no está instalada: pregunta si instalarla, fijar
## otra de las instaladas o usar la default. `then_open`: después de elegir
## otra versión, 1 lo abre en el editor, 0 lo corre, -1 nada.
func ask_missing(e: ProjectEntry, then_open := -1) -> void:
	var st: ProjectStatus = statuses.get(e.path)
	if st == null or st.missing_version().is_empty():
		return
	_open_after = {} if then_open < 0 else {"path": e.path, "edit": then_open == 1}
	var job := GmCli.read(GmCommands.list())
	await job.finished
	var r := GmParse.parse_list(job.stdout) if job.succeeded() else null
	_missing_installed.clear()
	_missing_default = ""
	if r != null and r.ok:
		_missing_installed.assign(r.value)
		for v in _missing_installed:
			if v.is_default:
				_missing_default = v.name
	_missing_for = e
	var suggested := MissingVersionDialog.best_same_minor(st.missing_version(), _missing_installed)
	_missing_suggested = suggested.name if suggested != null else ""
	%MissingVersionDialog.open_for(e.name, st.missing_version(), _missing_default,
		_missing_installed.size(), st.missing_source() == "default", _missing_suggested)


func _on_missing_choice(kind: StringName) -> void:
	var e := _missing_for
	var st: ProjectStatus = statuses.get(e.path) if e != null else null
	if st == null:
		return
	match kind:
		MissingVersionDialog.SUGGESTED:
			if not _missing_suggested.is_empty():
				change_version(GmCommands.set_local(e.path, _missing_suggested))
		MissingVersionDialog.INSTALL:
			_open_after = {}
			_on_install_requested(st.missing_version())
		MissingVersionDialog.OTHER:
			%ChangeVersionDialog.open_for(e, _missing_installed, st)
		MissingVersionDialog.DEFAULT:
			change_version(default_args(e, st, _missing_default))


## Cómo pasar `e` a la default: si lo fija su propio .godot-version, se borra;
## si viene de una carpeta de más arriba, borrarlo no alcanza y se fija la
## default en el proyecto.
static func default_args(e: ProjectEntry, st: ProjectStatus, default_name: String) -> PackedStringArray:
	var source := st.missing_source()
	if not source.is_empty() and source != "default" and ProjectEntry.normalize(source.get_base_dir()) == e.path:
		return GmCommands.unset_local(e.path)
	return GmCommands.set_local(e.path, default_name)


func _on_install_requested(version: String) -> void:
	%InstallDialog.open_install(RemoteVersion.unknown(version))


## Agrega la carpeta si tiene project.godot; si no, avisa.
## Corre `new` (con el panel de progreso) y, si quedó un project.godot, lo
## agrega a la lista; aunque fallen los plugins del preset, el proyecto existe.
func create_project(args: PackedStringArray, path: String) -> CliJob:
	var job := GmCli.write(args)
	job_started.emit(job, tr("Creando %s") % path.get_file())
	await job.finished
	if FileAccess.file_exists(path.path_join(ProjectEntry.PROJECT_FILE)):
		add_project(path)
	return job


func add_project(dir: String) -> bool:
	var e := ProjectEntry.read(dir)
	if e.missing:
		_show_message(tr("«%s» no tiene project.godot.\nPara buscar proyectos adentro de una carpeta, usá Escanear…") % e.path)
		return false
	if list.add(e.path):
		entries.append(e)
		_save()
		_set_status(tr("Se agregó «%s».") % e.name)
	else:
		_set_status(tr("«%s» ya estaba en la lista.") % e.name)
	_select_path(e.path)
	resolve_versions(PackedStringArray([e.path]))
	return true


func remove_project(path: String) -> void:
	if not list.remove(path):
		return
	var p := ProjectEntry.normalize(path)
	for i in entries.size():
		if entries[i].path == p:
			_set_status(tr("Se quitó «%s» de la lista.") % entries[i].name)
			entries.remove_at(i)
			break
	statuses.erase(p)
	if selected != null and selected.path == p:
		selected = null
	_save()
	_rebuild()


## Busca proyectos en `dir` en otro hilo y agrega los nuevos. Devuelve cuántos
## eran nuevos (-1 si ya había un escaneo en curso).
func scan_folder(dir: String) -> int:
	if is_scanning():
		return -1
	var root := ProjectEntry.normalize(dir)
	list.last_scan_dir = root
	_set_busy(true)
	_set_status(tr("Buscando proyectos en %s…") % root)
	_scan_thread = Thread.new()
	_scan_thread.start(ProjectList.scan.bind(root, ProjectList.SCAN_DEPTH))
	if entries.is_empty():
		_rebuild()  # Muestra "Buscando proyectos…" en lugar de la lista vacía.
	while _scan_thread.is_alive():
		await get_tree().process_frame
	var found: PackedStringArray = _scan_thread.wait_to_finish()
	_scan_thread = null
	var added := 0
	var new_paths := PackedStringArray()
	for p in found:
		if list.add(p):
			entries.append(ProjectEntry.read(p))
			new_paths.append(ProjectEntry.normalize(p))
			added += 1
	_save()
	_set_busy(false)
	if found.is_empty():
		_set_status(tr("No se encontraron proyectos en %s.") % root)
	else:
		_set_status(tr("Se encontraron %d proyectos en %s; %d nuevos.") % [found.size(), root, added])
	_rebuild()
	if not new_paths.is_empty():
		resolve_versions(new_paths)
	return added


## Agrega los proyectos de la lista del Project Manager (`cfg_path`) que
## existen y no estaban. Devuelve cuántos agregó.
func import_from_pm(cfg_path: String) -> int:
	if not FileAccess.file_exists(cfg_path):
		_show_message(tr("No se encontró la lista del Project Manager en\n%s") % cfg_path)
		return 0
	var pm := ProjectList.read_pm_list(cfg_path)
	var existing: PackedStringArray = pm["existing"]
	var gone: PackedStringArray = pm["gone"]
	var new_paths := PackedStringArray()
	for p in existing:
		if list.add(p):
			entries.append(ProjectEntry.read(p))
			new_paths.append(p)
	_save()
	var text := tr("Del Project Manager: %d nuevos, %d ya estaban.") % [new_paths.size(), existing.size() - new_paths.size()]
	if not gone.is_empty():
		text = tr("Del Project Manager: %d nuevos, %d ya estaban, %d ya no existen (no se agregaron).") % [
			new_paths.size(), existing.size() - new_paths.size(), gone.size()]
	_set_status(text)
	_status.tooltip_text = text + ("\n\n" + tr("No existen:") + "\n" + "\n".join(gone) if not gone.is_empty() else "")
	_rebuild()
	if not new_paths.is_empty():
		resolve_versions(new_paths)
	return new_paths.size()


func is_scanning() -> bool:
	return _scan_thread != null


## Los proyectos que se ven ahora, en orden.
func visible_projects() -> Array[ProjectEntry]:
	return ProjectList.apply(entries, _search.text, list.sort)


func _rebuild() -> void:
	# Si el foco estaba en una fila, vuelve a la lista después de recrearla.
	var focus := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var had_focus := focus != null and _rows.is_ancestor_of(focus)
	if had_focus:
		focus.release_focus()
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var shown := visible_projects()
	var keep: ProjectEntry = null
	for e in shown:
		var row := ROW_SCENE.instantiate()
		row.setup(e)
		row.selected.connect(_on_row_selected)
		row.activated.connect(_on_row_activated)
		row.context_requested.connect(_on_row_context)
		row.open_requested.connect(func(edit: bool) -> void:
			_on_row_selected(row)
			open_selected(edit))
		row.install_requested.connect(func(_v: String) -> void:
			_on_row_selected(row)
			ask_missing(e))
		row.set_status(statuses.get(e.path))
		_rows.add_child(row)
		if selected != null and e.path == selected.path:
			keep = e
			row.is_selected = true
	if shown.is_empty() and is_scanning():
		_placeholder.show_state(tr("Buscando proyectos en %s…") % list.last_scan_dir, ListState.Kind.LOADING)
		_rows.get_parent().visible = false
	elif shown.is_empty() and entries.is_empty():
		_placeholder.show_state(tr("Todavía no hay proyectos.\nAgregá una carpeta con project.godot, buscalos dentro de una carpeta o traé los que ya tiene el Project Manager de Godot."), ListState.Kind.INFO, [
				[tr("Agregar…"), func() -> void: %Add.pressed.emit()],
				[tr("Escanear…"), func() -> void: %Scan.pressed.emit()],
				[tr("Importar de Godot"), func() -> void: %ImportPM.pressed.emit()]])
		_rows.get_parent().visible = false
	elif shown.is_empty():
		_placeholder.show_state(tr("Ningún proyecto coincide con la búsqueda."), ListState.Kind.INFO,
			[[tr("Mostrar todos"), func() -> void:
				_search.text = ""
				_rebuild()]])
		_rows.get_parent().visible = false
	else:
		_placeholder.visible = false
		_rows.get_parent().visible = true
	_select(keep)
	if had_focus:
		focus_list.call_deferred()


func _select_path(path: String) -> void:
	for e in entries:
		if e.path == path:
			selected = e
	_rebuild()
	var scroll := _rows.get_parent() as ScrollContainer
	for row in _rows.get_children():
		if row.is_selected:
			# Diferido para que ya tenga tamaño; la fila puede no existir más.
			(func() -> void:
				if is_instance_valid(row) and row.is_inside_tree() and scroll.is_ancestor_of(row):
					scroll.ensure_control_visible(row)).call_deferred()


## Clic derecho en una fila: la selecciona y muestra sus acciones.
func _on_row_context(row: Control, at: Vector2) -> PopupMenu:
	_on_row_selected(row)
	# Instalar… de la fila solo se ve si a su versión le falta instalar.
	return RowMenu.popup(self, [row.get_node("%Install"), null, %Open, %Run, null, %ChangeVersion,
		%Details, %ShowFolder, null, %Remove], at)


func _on_row_selected(row: Control) -> void:
	for r in _rows.get_children():
		r.is_selected = r == row
	_select(row.project)


func _on_row_activated(row: Control) -> void:
	_on_row_selected(row)
	var open: Button = %Open
	if not open.disabled:
		open.pressed.emit()


func _select(e: ProjectEntry) -> void:
	var changed := e != selected
	selected = e
	_update_actions()
	if changed:
		selection_changed.emit(e)


func _update_actions() -> void:
	var none := selected == null
	%Remove.disabled = none
	for button: Button in [%ShowFolder, %Open, %Run, %ChangeVersion, %Details]:
		button.disabled = none or selected.missing
	_update_inspector()


## El panel de la derecha: nombre, carpeta y versión del seleccionado.
func _update_inspector() -> void:
	%Empty.visible = selected == null
	%Actions.visible = selected != null
	if selected == null:
		return
	%InspName.text = selected.name
	%InspPath.text = selected.path
	var st: ProjectStatus = statuses.get(selected.path)
	var has_version := st != null and st.resolution != null
	%InspUses.visible = st != null
	if st != null:
		# Sin versión resuelta (buscando, no instalada, error) va el estado solo.
		%InspUses.text = tr("Abre con %s") % st.text() if has_version else st.text()
		if st.is_error():
			%InspUses.add_theme_color_override(&"font_color", ERROR_COLOR)
		else:
			%InspUses.remove_theme_color_override(&"font_color")
	%Open.text = tr("Abrir en %s") % st.resolution.version if has_version else tr("Abrir")


func _set_busy(busy: bool) -> void:
	%Scan.disabled = busy
	%Add.disabled = busy
	%ImportPM.disabled = busy


func _set_status(text: String) -> void:
	_status.text = text
	_status.tooltip_text = text


func _show_message(text: String) -> void:
	_message.dialog_text = text
	_message.reset_size()
	_message.popup_centered()


func _save() -> void:
	var err := list.save(list_path)
	if err != OK:
		_set_status(tr("No se pudo guardar la lista de proyectos (%s).") % error_string(err))


## Carpeta inicial de los selectores: la pedida si existe; si no, el home.
static func _start_dir(wanted: String) -> String:
	if not wanted.is_empty() and DirAccess.dir_exists_absolute(wanted):
		return wanted
	var home := OS.get_environment("USERPROFILE" if OS.get_name() == "Windows" else "HOME")
	return home if not home.is_empty() else OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
