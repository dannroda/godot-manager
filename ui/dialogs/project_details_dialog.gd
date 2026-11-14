extends AcceptDialog
## Detalles de un proyecto: carpeta, con qué Godot se guardó, con qué versión
## abre, y sus plugins de editor con botones para activarlos, desactivarlos o
## desinstalarlos. Sirve para destrabar un proyecto que no abre por un plugin
## roto. Los plugins los lee y los cambia el CLI (`--dir <p> plugins …`), no
## la UI. `open_for(project, status)` lo llena, lo muestra y pide la lista.

## Un plugin se activó, desactivó o desinstaló (lo usan los tests).
signal plugins_changed

var project: ProjectEntry
var plugins: Array[ProjectPlugin] = []
## Hay un comando del CLI en curso: los botones de las filas quedan apagados.
var busy := false

@onready var _name: Label = %ProjectName
@onready var _folder: Label = %Folder
@onready var _created: Label = %CreatedWith
@onready var _opens: Label = %OpensWith
@onready var _status: Label = %PluginsStatus
@onready var _rows: VBoxContainer = %Plugins
@onready var _reload: Button = %Reload
@onready var _remove_dialog: ConfirmationDialog = %RemoveDialog

var _to_remove: ProjectPlugin


func _ready() -> void:
	_reload.pressed.connect(func() -> void: load_plugins())
	_remove_dialog.confirmed.connect(func() -> void:
		if _to_remove != null:
			remove_plugin(_to_remove))


## Llena los datos del proyecto (sin pedir los plugins).
func fill(p: ProjectEntry, status: ProjectStatus) -> void:
	project = p
	_name.text = p.name
	_folder.text = p.path
	_folder.tooltip_text = p.path
	var made := p.created_with()
	_created.text = made if not made.is_empty() else tr("no se sabe")
	_opens.text = status.text() if status != null else "…"
	show_plugins([])
	_set_status(tr("Leyendo plugins…"))


func open_for(p: ProjectEntry, status: ProjectStatus) -> void:
	fill(p, status)
	popup_centered_clamped(Vector2i(680, 620))
	get_ok_button().grab_focus()
	load_plugins()


## Pide la lista al CLI y la muestra (o el error).
func load_plugins() -> void:
	if project == null:
		return
	if not GmCli.available:
		_set_status(tr("godot-manager no está disponible: revisá Ajustes."))
		return
	_set_busy(true)
	_set_status(tr("Leyendo plugins…"))
	var job := GmCli.read(GmCommands.plugins(project.path))
	job.notify_on_error = false
	await job.finished
	_set_busy(false)
	var r := GmParse.parse_plugins(job.stdout) if job.start_error == null else null
	if r != null and r.ok and job.succeeded():
		show_plugins(r.value)
		return
	show_plugins([])
	_set_status(_error_text(r.error if r != null and not r.ok else GmParse.job_error(job), job))


## Muestra `list` (de ProjectPlugin) como filas.
func show_plugins(list: Array) -> void:
	plugins.assign(list)
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for p in plugins:
		_rows.add_child(_make_row(p))
	_rows.get_parent().get_parent().visible = not plugins.is_empty()
	var active := 0
	var broken := 0
	for p in plugins:
		if p.enabled:
			active += 1
		if p.has_problems():
			broken += 1
	if plugins.is_empty():
		_set_status(tr("El proyecto no tiene plugins en addons/."))
	elif broken > 0:
		_set_status(tr("Plugins: %d · activos: %d · con problemas: %d") % [plugins.size(), active, broken])
	else:
		_set_status(tr("Plugins: %d · activos: %d") % [plugins.size(), active])
	_set_busy(busy)


## Activa o desactiva `p` y vuelve a leer la lista.
func set_enabled(p: ProjectPlugin, enable: bool) -> CliJob:
	return await _write(GmCommands.plugin_enable(project.path, p.id, enable),
		(tr("Se activó «%s».") if enable else tr("Se desactivó «%s».")) % p.display_name())


func remove_plugin(p: ProjectPlugin) -> CliJob:
	return await _write(GmCommands.plugin_remove(project.path, p.id),
		tr("Se desinstaló «%s».") % p.display_name())


## Pide confirmación para desinstalar `p`.
func ask_remove(p: ProjectPlugin) -> void:
	_to_remove = p
	if p.missing:
		_remove_dialog.dialog_text = tr("¿Quitar «%s» de project.godot?\nSu carpeta ya no existe.") % p.display_name()
	else:
		_remove_dialog.dialog_text = tr("¿Desinstalar «%s»?\nSe desactiva y se borra la carpeta:\n%s\n\nNo se puede deshacer.") % [
			p.display_name(), p.path]
	_remove_dialog.reset_size()
	_remove_dialog.popup_centered()
	_remove_dialog.get_cancel_button().grab_focus()


func _write(args: PackedStringArray, done_text: String) -> CliJob:
	_set_busy(true)
	var job := GmCli.write(args)
	job.notify_on_error = false
	await job.finished
	_set_busy(false)
	if job.succeeded():
		plugins_changed.emit()
		await load_plugins()
		_set_status(done_text)
	else:
		var r := GmParse.parse_ok(job.stdout) if job.start_error == null else null
		_set_status(_error_text(r.error if r != null and not r.ok else GmParse.job_error(job), job))
		await load_plugins()
	return job


func _make_row(p: ProjectPlugin) -> Control:
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
	title.text = p.display_name() + ("  " + p.version if not p.version.is_empty() else "")
	info.add_child(title)
	var meta := Label.new()
	meta.theme_type_variation = &"DimLabel"
	meta.text = "addons/" + p.id + ((" · " + p.author) if not p.author.is_empty() else "")
	meta.tooltip_text = p.path
	meta.mouse_filter = Control.MOUSE_FILTER_PASS
	info.add_child(meta)
	if not p.description.is_empty():
		var desc := Label.new()
		desc.text = p.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size.x = 300
		info.add_child(desc)
	for problem in p.problems:
		var warn := Label.new()
		warn.name = "Problem"
		warn.text = "⚠ " + problem
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.custom_minimum_size.x = 300
		warn.add_theme_color_override("font_color", Color(1, 0.7058824, 0.3019608))
		info.add_child(warn)

	var actions := VBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(actions)
	var toggle := CheckButton.new()
	toggle.name = "Enabled"
	toggle.text = tr("Activo")
	toggle.button_pressed = p.enabled
	# Uno sin carpeta solo se puede desactivar.
	toggle.set_meta(&"locked", p.missing and not p.enabled)
	toggle.disabled = toggle.get_meta(&"locked")
	toggle.tooltip_text = tr("Activa o desactiva el plugin en project.godot")
	toggle.toggled.connect(func(on: bool) -> void: set_enabled(p, on))
	actions.add_child(toggle)
	var remove := Button.new()
	remove.name = "Remove"
	remove.text = tr("Quitar") if p.missing else tr("Desinstalar…")
	remove.tooltip_text = tr("Lo saca de project.godot") if p.missing else tr("Lo desactiva y borra su carpeta")
	remove.pressed.connect(func() -> void: ask_remove(p))
	actions.add_child(remove)
	return panel


func _set_busy(value: bool) -> void:
	busy = value
	_reload.disabled = value
	for row in _rows.get_children():
		for button: BaseButton in [row.find_child("Enabled", true, false), row.find_child("Remove", true, false)]:
			if button != null:
				button.disabled = value or button.get_meta(&"locked", false)


func _set_status(text: String) -> void:
	_status.text = text
	_status.tooltip_text = text


func _error_text(err: CliError, job: CliJob) -> String:
	if err == null:
		return tr("godot-manager terminó con código %d") % job.exit_code
	if err.code == "unknown_command" or (err.code == "invalid_args" and err.message.contains("plugins")):
		return tr("Este godot-manager no maneja plugins: hace falta la versión 2.3 o posterior.")
	return err.message
