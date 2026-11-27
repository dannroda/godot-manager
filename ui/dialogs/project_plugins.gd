class_name ProjectPlugins
extends VBoxContainer
## Plugins de un proyecto, en el panel de Proyectos: sus plugins de editor con
## botones para activarlos, desactivarlos o desinstalarlos (sirve para
## destrabar un proyecto que no abre por un plugin roto). Además (2.4+) agrega
## plugins del Asset Store o de GitHub, busca y aplica versiones nuevas que
## anden con el Godot del proyecto, fija o suelta versiones, instala lo que
## falta de plugins.json y aplica o guarda presets.
## Los plugins los lee y los cambia el CLI (`--dir <p> plugins …`), no la UI.
## `open_for(project)` lo llena y pide la lista.

## Un plugin se activó, desactivó, instaló o desinstaló (lo usan los tests).
signal plugins_changed

var project: ProjectEntry
var plugins: Array[ProjectPlugin] = []
## Hay un comando del CLI en curso: los botones quedan apagados.
var busy := false
## Lo último de `plugins outdated`: nombre en plugins.lock → PluginUpdate.
var updates := {}
var presets: Array[PluginPreset] = []

@onready var _status: Label = %PluginsStatus
@onready var _rows: VBoxContainer = %Plugins
@onready var _reload: Button = %Reload
@onready var _remove_dialog: ConfirmationDialog = %RemoveDialog
@onready var _add: Button = %AddPlugin
@onready var _check: Button = %CheckUpdates
@onready var _update_all: Button = %UpdateAll
@onready var _install: Button = %InstallPending
@onready var _presets_menu: MenuButton = %Presets
@onready var _add_dialog: AcceptDialog = %AddPluginDialog
@onready var _save_dialog: ConfirmationDialog = %SavePresetDialog
@onready var _preset_name: LineEdit = %PresetName
@onready var _preset_pin: CheckBox = %PresetPin

var _to_remove: ProjectPlugin

## Ítems fijos del menú de presets; los demás son "Aplicar «nombre»".
const MENU_SAVE := 1000


func _ready() -> void:
	_reload.pressed.connect(func() -> void: load_plugins())
	# El panel se llena al elegir un proyecto, que puede ser antes de que el
	# CLI esté listo (al arrancar): cuando lo está, se vuelve a pedir.
	GmCli.availability_changed.connect(func(ok: bool, _m: String) -> void:
		if ok and project != null:
			load_presets()
			load_plugins())
	_remove_dialog.confirmed.connect(func() -> void:
		if _to_remove != null:
			remove_plugin(_to_remove))
	_add.pressed.connect(func() -> void:
		if project != null:
			_add_dialog.open_for(project.path))
	_add_dialog.add_requested.connect(func(source: String, pin: bool) -> void: add_plugin(source, pin))
	_check.pressed.connect(func() -> void: check_updates())
	_update_all.pressed.connect(func() -> void: update_plugins([]))
	_install.pressed.connect(func() -> void:
		_write(GmCommands.plugin_install(project.path), tr("Se instalaron los plugins de plugins.json.")))
	_presets_menu.get_popup().id_pressed.connect(_on_preset_menu)
	_save_dialog.confirmed.connect(func() -> void:
		var name := _preset_name.text.strip_edges()
		if not name.is_empty():
			save_preset(name, _preset_pin.button_pressed))
	_preset_name.text_submitted.connect(func(_t: String) -> void:
		_save_dialog.hide()
		_save_dialog.confirmed.emit())


## Pasa a `p` (sin pedir los plugins).
func fill(p: ProjectEntry) -> void:
	project = p
	updates = {}
	show_plugins([])
	_set_status(tr("Leyendo plugins…"))


func open_for(p: ProjectEntry) -> void:
	fill(p)
	load_presets()
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
	var path := project.path
	var job := GmCli.read(GmCommands.plugins(path))
	job.notify_on_error = false
	await job.finished
	# Se eligió otro proyecto mientras tanto: esta respuesta ya no va.
	if project == null or project.path != path:
		return
	_set_busy(false)
	var r := GmParse.parse_plugins(job.stdout) if job.start_error == null else null
	if r != null and r.ok and job.succeeded():
		show_plugins(r.value)
		return
	show_plugins([])
	_set_status(_error_text(r.error if r != null and not r.ok else GmParse.job_error(job), job))


## Los presets, para el menú (sin trabar nada: si falla, el menú queda solo
## con "Guardar como preset…").
func load_presets() -> void:
	if not GmCli.available:
		show_presets([])
		return
	var job := GmCli.read(GmCommands.presets())
	job.notify_on_error = false
	await job.finished
	var r := GmParse.parse_presets(job.stdout) if job.start_error == null else null
	show_presets(r.value if r != null and r.ok else [])


func show_presets(list: Array) -> void:
	presets.assign(list)
	var menu := _presets_menu.get_popup()
	menu.clear()
	for i in presets.size():
		menu.add_item(tr("Aplicar «%s»") % presets[i].name, i)
		menu.set_item_tooltip(menu.get_item_count() - 1, presets[i].summary())
	if not presets.is_empty():
		menu.add_separator()
	menu.add_item(tr("Guardar como preset…"), MENU_SAVE)
	menu.set_item_tooltip(menu.get_item_count() - 1, tr("Guarda los plugins de plugins.json de este proyecto para usarlos en otros"))


## Muestra `list` (de ProjectPlugin) como filas.
func show_plugins(list: Array) -> void:
	plugins.assign(list)
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for p in plugins:
		_rows.add_child(_make_row(p))
	_rows.get_parent().get_parent().visible = not plugins.is_empty()
	var installed := 0
	var active := 0
	var broken := 0
	var pending := 0
	var assets := 0
	for p in plugins:
		if p.pending:
			pending += 1
			continue
		if p.asset:
			assets += 1
			continue
		installed += 1
		if p.enabled:
			active += 1
		if p.has_problems():
			broken += 1
	var text := ""
	if plugins.is_empty():
		text = tr("El proyecto no tiene plugins en addons/.")
	elif broken > 0:
		text = tr("Plugins: %d · activos: %d · con problemas: %d") % [installed, active, broken]
	else:
		text = tr("Plugins: %d · activos: %d") % [installed, active]
	if assets > 0:
		text += " · " + tr("recursos: %d") % assets
	if pending > 0:
		text += " · " + tr("sin instalar: %d") % pending
	_set_status(text)
	_install.visible = pending > 0
	_update_all.visible = not updatable().is_empty()
	_set_busy(busy)


## Los nombres (de plugins.lock) que tienen una versión nueva y no están fijados.
func updatable() -> PackedStringArray:
	var names: PackedStringArray = []
	for p in plugins:
		var u: PluginUpdate = updates.get(p.managed_name)
		if p.is_managed() and not p.pending and not p.pinned and u != null and u.newer:
			names.append(p.managed_name)
	return names


## Activa o desactiva `p` y vuelve a leer la lista.
func set_enabled(p: ProjectPlugin, enable: bool) -> CliJob:
	return await _write(GmCommands.plugin_enable(project.path, p.id, enable),
		(tr("Se activó «%s».") if enable else tr("Se desactivó «%s».")) % p.display_name())


func remove_plugin(p: ProjectPlugin) -> CliJob:
	var target := p.managed_name if p.pending or p.asset else p.id
	return await _write(GmCommands.plugin_remove(project.path, target),
		tr("Se desinstaló «%s».") % p.display_name())


func add_plugin(source: String, pin := false) -> CliJob:
	return await _write(GmCommands.plugin_add(project.path, source, pin), tr("Se instaló «%s».") % source)


func update_plugins(names: PackedStringArray) -> CliJob:
	var job := await _write(GmCommands.plugin_update(project.path, names),
		tr("Se actualizaron los plugins.") if names.is_empty() else tr("Se actualizó «%s».") % ", ".join(names))
	if job.succeeded():
		for n in (names if not names.is_empty() else updatable()):
			updates.erase(n)
		show_plugins(plugins)
	return job


func set_pinned(p: ProjectPlugin, pin: bool) -> CliJob:
	var args := GmCommands.plugin_pin(project.path, p.managed_name) if pin else GmCommands.plugin_unpin(project.path, p.managed_name)
	return await _write(args, (tr("«%s» quedó fijado en %s.") % [p.display_name(), p.locked_version]) if pin
		else tr("«%s» ya no está fijado.") % p.display_name())


func apply_preset(preset: PluginPreset) -> CliJob:
	return await _write(GmCommands.plugin_apply(project.path, preset.name), tr("Se aplicó el preset «%s».") % preset.name)


func save_preset(name: String, pin: bool) -> CliJob:
	var job := await _write(GmCommands.preset_save(project.path, name, pin), tr("Se guardó el preset «%s».") % name, false)
	load_presets()
	return job


## Pregunta a las fuentes por versiones nuevas que anden con el Godot del proyecto.
func check_updates() -> void:
	if project == null or busy:
		return
	_set_busy(true)
	_set_status(tr("Buscando versiones nuevas…"))
	var job := GmCli.read(GmCommands.plugin_outdated(project.path))
	job.notify_on_error = false
	await job.finished
	_set_busy(false)
	var r := GmParse.parse_plugin_outdated(job.stdout) if job.start_error == null else null
	if r == null or not r.ok:
		_set_status(_error_text(r.error if r != null else GmParse.job_error(job), job))
		return
	show_updates(r.value)


func show_updates(list: Array) -> void:
	updates = {}
	var newer := 0
	for u: PluginUpdate in list:
		updates[u.name] = u
		if u.newer:
			newer += 1
	show_plugins(plugins)
	if list.is_empty():
		_set_status(tr("No hay plugins instalados con «Agregar plugin»: solo esos se pueden actualizar."))
	elif newer == 0:
		_set_status(tr("Los plugins están al día para este Godot."))
	else:
		_set_status(tr("Hay versiones nuevas: %d") % newer)


## Pide confirmación para desinstalar `p`.
func ask_remove(p: ProjectPlugin) -> void:
	_to_remove = p
	if p.pending:
		_remove_dialog.dialog_text = tr("¿Sacar «%s» de plugins.json?\nTodavía no está instalado.") % p.display_name()
	elif p.missing:
		_remove_dialog.dialog_text = tr("¿Quitar «%s» de project.godot?\nSu carpeta ya no existe.") % p.display_name()
	elif p.asset:
		_remove_dialog.dialog_text = tr("¿Desinstalar «%s»?\nSe borran sus carpetas:\n%s\n\nNo se puede deshacer.") % [
			p.display_name(), "\n".join(p.folders)]
	else:
		_remove_dialog.dialog_text = tr("¿Desinstalar «%s»?\nSe desactiva y se borra la carpeta:\n%s\n\nNo se puede deshacer.") % [
			p.display_name(), p.path]
	_remove_dialog.reset_size()
	_remove_dialog.popup_centered()
	_remove_dialog.get_cancel_button().grab_focus()


func _on_preset_menu(id: int) -> void:
	if id == MENU_SAVE:
		_preset_name.text = ""
		_preset_pin.button_pressed = false
		_save_dialog.popup_centered()
		_preset_name.grab_focus()
	elif id >= 0 and id < presets.size():
		apply_preset(presets[id])


## Corre una escritura del CLI; mientras dura, el estado muestra sus pasos (los
## comandos de plugins que bajan cosas emiten eventos). `reload`: volver a leer
## la lista al terminar.
func _write(args: PackedStringArray, done_text: String, reload := true) -> CliJob:
	_set_busy(true)
	var job := GmCli.write(args)
	job.notify_on_error = false
	job.line_received.connect(func(stream: CliJob.Stream, line: String) -> void:
		if stream != CliJob.Stream.STDOUT:
			return
		var ev := GmParse.parse_event(line)
		if ev.ok and (ev.value as CliEvent).kind == CliEvent.Kind.STEP:
			_set_status((ev.value as CliEvent).message))
	await job.finished
	_set_busy(false)
	if job.succeeded():
		plugins_changed.emit()
		if reload:
			await load_plugins()
		_set_status(done_text)
	else:
		var err := GmParse.job_error(job)
		if err == null:
			var r := GmParse.parse_ok(job.stdout) if job.start_error == null else null
			err = r.error if r != null and not r.ok else null
		if reload:
			await load_plugins()
		_set_status(_error_text(err, job))
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
	var version := p.locked_version if p.pending or p.asset else p.version
	title.text = p.display_name() + ("  " + version if not version.is_empty() else "")
	title.tooltip_text = title.text
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.custom_minimum_size.x = 60
	info.add_child(title)
	var meta := Label.new()
	meta.name = "Meta"
	meta.theme_type_variation = &"DimLabel"
	var bits: PackedStringArray = []
	if p.pending:
		bits.append(tr("sin instalar"))
	elif p.asset:
		bits.append(tr("Recursos (sin plugin de editor)"))
		bits.append(folders_summary(p.folders))
	else:
		bits.append("addons/" + p.id)
		if not p.author.is_empty():
			bits.append(p.author)
	if p.is_managed():
		bits.append(p.source)
		if p.pinned:
			bits.append(tr("fijado"))
	meta.text = " · ".join(bits)
	meta.tooltip_text = p.path if not p.asset else tr("No trae plugin.cfg: son archivos para el proyecto (arte, sonido, scripts…), no hay nada que activar.") + "\n\n" + "\n".join(p.folders)
	meta.mouse_filter = Control.MOUSE_FILTER_PASS
	# Una línea larga se corta (con el texto entero en el tooltip): no ensancha el panel.
	meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	meta.custom_minimum_size.x = 60
	info.add_child(meta)
	if not p.description.is_empty():
		var desc := Label.new()
		desc.text = p.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(desc)
	var u: PluginUpdate = updates.get(p.managed_name) if p.is_managed() else null
	if u != null:
		var notes: PackedStringArray = []
		if u.newer:
			notes.append(tr("Nueva: %s") % u.latest)
		if not u.blocked_version.is_empty():
			notes.append(tr("%s pide %s") % [u.blocked_version, u.blocked_godot()])
		if u.incompatible:
			notes.append(tr("la instalada no anda con el Godot del proyecto"))
		if not notes.is_empty():
			var note := Label.new()
			note.name = "UpdateNote"
			note.text = " · ".join(notes)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.add_theme_color_override("font_color", Color(0.4392157, 0.7294118, 0.9803922))
			info.add_child(note)
	for problem in p.problems:
		var warn := Label.new()
		warn.name = "Problem"
		warn.text = "⚠ " + problem
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.add_theme_color_override("font_color", Color(1, 0.7058824, 0.3019608))
		info.add_child(warn)

	var actions := VBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(actions)
	if not p.pending and not p.asset:
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
	if u != null and u.newer and not p.pinned:
		var update := Button.new()
		update.name = "Update"
		update.text = tr("Actualizar")
		update.tooltip_text = tr("Instala %s (no pisa archivos cambiados a mano)") % u.latest
		update.pressed.connect(func() -> void: update_plugins(PackedStringArray([p.managed_name])))
		actions.add_child(update)
	if p.is_managed() and not p.pending:
		var pin := Button.new()
		pin.name = "Pin"
		pin.text = tr("Soltar") if p.pinned else tr("Fijar")
		pin.tooltip_text = tr("Vuelve a seguir la versión más nueva que ande") if p.pinned \
			else tr("Queda en %s: Actualizar no lo toca") % p.locked_version
		pin.pressed.connect(func() -> void: set_pinned(p, not p.pinned))
		actions.add_child(pin)
	var remove := Button.new()
	remove.name = "Remove"
	if p.asset:
		remove.text = tr("Desinstalar…")
		remove.tooltip_text = tr("Borra sus carpetas")
	elif p.pending:
		remove.text = tr("Quitar")
		remove.tooltip_text = tr("Lo saca de plugins.json")
	else:
		remove.text = tr("Quitar") if p.missing else tr("Desinstalar…")
		remove.tooltip_text = tr("Lo saca de project.godot") if p.missing else tr("Lo desactiva y borra su carpeta")
	remove.pressed.connect(func() -> void: ask_remove(p))
	actions.add_child(remove)
	return panel


## Las primeras carpetas y cuántas más ("A, B y 5 más").
static func folders_summary(folders: PackedStringArray, shown := 2) -> String:
	if folders.size() <= shown + 1:
		return ", ".join(folders)
	return TranslationServer.translate("%s y %d más") % [", ".join(folders.slice(0, shown)), folders.size() - shown]


func _set_busy(value: bool) -> void:
	busy = value
	_reload.disabled = value
	for b: BaseButton in [_add, _check, _update_all, _install, _presets_menu]:
		b.disabled = value
	for row in _rows.get_children():
		for name: String in ["Enabled", "Remove", "Update", "Pin"]:
			var button := row.find_child(name, true, false) as BaseButton
			if button != null:
				button.disabled = value or button.get_meta(&"locked", false)


func _set_status(text: String) -> void:
	_status.text = text
	_status.tooltip_text = text


func _error_text(err: CliError, job: CliJob) -> String:
	if err == null:
		return tr("godot-manager terminó con código %d") % job.exit_code
	if err.code == "unknown_command" or (err.code == "invalid_args" and err.message.contains("subcomando desconocido")):
		return tr("Este godot-manager no maneja esto: hace falta una versión más nueva (Ajustes).")
	return err.message
