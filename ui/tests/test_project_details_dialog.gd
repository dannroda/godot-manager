extends TestCase
## Detalles del proyecto (m3-06): filas de plugins y, contra el CLI real
## (GM_BIN), activar, desactivar y desinstalar en un proyecto temporal.

const DIALOG := preload("res://dialogs/project_details_dialog.tscn")

var dialog: AcceptDialog
var fx: CliFixture
var project_dir := ""
var _old_binary := ""
var _old_available := false


func before_each() -> void:
	dialog = DIALOG.instantiate()
	tree.root.add_child(dialog)
	_old_binary = GmCli.binary
	_old_available = GmCli.available


func after_each() -> void:
	GmCli.binary = _old_binary
	GmCli.available = _old_available
	dialog.queue_free()
	if not project_dir.is_empty():
		_remove_tree(project_dir)
		project_dir = ""
	await wait_frames(1)


func _plugin(id: String, enabled := true, problems: PackedStringArray = [], missing := false) -> ProjectPlugin:
	var p := ProjectPlugin.new()
	p.id = id
	p.name = id.capitalize()
	p.enabled = enabled
	p.problems = problems
	p.missing = missing
	p.path = "/p/addons/" + id
	return p


func _rows() -> Array[Node]:
	return dialog.get_node("%Plugins").get_children()


func _status() -> String:
	return (dialog.get_node("%PluginsStatus") as Label).text


func test_rows_and_status() -> void:
	var list: Array[ProjectPlugin] = [_plugin("a"), _plugin("b", false, ["falta el script"]), _plugin("c", true, [], true)]
	dialog.show_plugins(list)
	assert_eq(_rows().size(), 3)
	assert_eq(_status(), "Plugins: 3 · activos: 2 · con problemas: 1")
	var b := _rows()[1]
	assert_false((b.find_child("Enabled", true, false) as CheckButton).button_pressed)
	assert_eq((b.find_child("Problem", true, false) as Label).text, "⚠ falta el script")
	# El que no tiene carpeta se puede desactivar y "Quitar".
	var c := _rows()[2]
	assert_false((c.find_child("Enabled", true, false) as CheckButton).disabled)
	assert_eq((c.find_child("Remove", true, false) as Button).text, "Quitar")


func test_empty() -> void:
	dialog.show_plugins([])
	assert_eq(_status(), "El proyecto no tiene plugins en addons/.")
	assert_false((dialog.get_node("Content/ListPanel") as Control).visible)


func test_busy_disables_rows() -> void:
	dialog.show_plugins([_plugin("a")] as Array[ProjectPlugin])
	dialog._set_busy(true)
	assert_true((_rows()[0].find_child("Remove", true, false) as Button).disabled)
	dialog._set_busy(false)
	assert_false((_rows()[0].find_child("Remove", true, false) as Button).disabled)


func _setup_cli() -> bool:
	fx = CliFixture.new()
	if not fx.available():
		skip(fx.why_unavailable())
		return false
	GmCli.binary = fx.gm_bin
	GmCli.available = true
	project_dir = OS.get_user_data_dir().path_join("test_plugins_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(project_dir.path_join("addons/good"))
	DirAccess.make_dir_recursive_absolute(project_dir.path_join("addons/broken"))
	_write("project.godot", "config_version=5\n\n[application]\n\nconfig/name=\"Con plugins\"\n\n[editor_plugins]\n\nenabled=PackedStringArray(\"res://addons/good/plugin.cfg\", \"res://addons/broken/plugin.cfg\")\n")
	_write("addons/good/plugin.cfg", "[plugin]\n\nname=\"Good\"\nversion=\"1.0\"\nscript=\"plugin.gd\"\n")
	_write("addons/good/plugin.gd", "@tool\nextends EditorPlugin\n")
	_write("addons/broken/plugin.cfg", "[plugin]\n\nname=\"Broken\"\nscript=\"no_existe.gd\"\n")
	return true


func _write(rel: String, text: String) -> void:
	var f := FileAccess.open(project_dir.path_join(rel), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _project_godot() -> String:
	return FileAccess.get_file_as_string(project_dir.path_join("project.godot"))


func test_disable_and_remove_with_cli() -> void:
	if not _setup_cli():
		return
	dialog.fill(ProjectEntry.read(project_dir), null)
	await dialog.load_plugins()
	assert_eq(dialog.plugins.size(), 2)
	assert_eq(_status(), "Plugins: 2 · activos: 2 · con problemas: 1")
	var broken: ProjectPlugin = dialog.plugins[0]
	assert_eq(broken.id, "broken")

	var job: CliJob = await dialog.set_enabled(broken, false)
	assert_true(job.succeeded(), job.stdout)
	assert_eq(_status(), "Se desactivó «Broken».")
	assert_false(_project_godot().contains("addons/broken"))
	assert_true(_project_godot().contains("res://addons/good/plugin.cfg"))
	assert_false((dialog.plugins[0] as ProjectPlugin).enabled)

	job = await dialog.remove_plugin(dialog.plugins[1])
	assert_true(job.succeeded(), job.stdout)
	assert_false(DirAccess.dir_exists_absolute(project_dir.path_join("addons/good")))
	assert_eq(dialog.plugins.size(), 1)
	assert_true(_project_godot().contains("enabled=PackedStringArray()"))


func test_not_a_project_with_cli() -> void:
	if not _setup_cli():
		return
	DirAccess.remove_absolute(project_dir.path_join("project.godot"))
	var e := ProjectEntry.new()
	e.path = project_dir
	e.name = "x"
	dialog.fill(e, null)
	await dialog.load_plugins()
	assert_true(_status().contains("no es un proyecto"), _status())


func _remove_tree(dir: String) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _managed(id: String, pinned := false) -> ProjectPlugin:
	var p := _plugin(id)
	p.managed_name = id + "-plugin"
	p.source = "store:pub/" + id
	p.locked_version = "v1.0.0"
	p.pinned = pinned
	return p


func _update(name: String, latest: String, newer: bool, blocked := "") -> PluginUpdate:
	var u := PluginUpdate.new()
	u.name = name
	u.version = "v1.0.0"
	u.latest = latest
	u.newer = newer
	u.blocked_version = blocked
	u.blocked_min = "4.6" if not blocked.is_empty() else ""
	return u


func test_managed_and_pending_rows() -> void:
	var pending := ProjectPlugin.new()
	pending.pending = true
	pending.managed_name = "later"
	pending.name = "later"
	pending.source = "github:a/later"
	dialog.show_plugins([_managed("a", true), _plugin("b"), pending] as Array[ProjectPlugin])
	assert_eq(_status(), "Plugins: 2 · activos: 2 · sin instalar: 1")
	var a := _rows()[0]
	assert_has((a.find_child("Meta", true, false) as Label).text, "store:pub/a · fijado")
	assert_eq((a.find_child("Pin", true, false) as Button).text, "Soltar")
	assert_true(_rows()[1].find_child("Pin", true, false) == null, "instalado a mano: no se fija")
	var later := _rows()[2]
	assert_true(later.find_child("Enabled", true, false) == null, "sin instalar no se activa")
	assert_has((later.find_child("Meta", true, false) as Label).text, "sin instalar")
	assert_true((dialog.get_node("%InstallPending") as Button).visible)


func test_updates_show_on_rows() -> void:
	dialog.show_plugins([_managed("a"), _managed("b", true), _managed("c")] as Array[ProjectPlugin])
	assert_false((dialog.get_node("%UpdateAll") as Button).visible)
	dialog.show_updates([_update("a-plugin", "v2.0.0", true), _update("b-plugin", "v2.0.0", true),
		_update("c-plugin", "v1.0.0", false, "v3.0.0")])
	assert_eq(_status(), "Hay versiones nuevas: 2")
	assert_eq(dialog.updatable(), PackedStringArray(["a-plugin"]), "el fijado no")
	assert_true((dialog.get_node("%UpdateAll") as Button).visible)
	assert_eq((_rows()[0].find_child("UpdateNote", true, false) as Label).text, "Nueva: v2.0.0")
	assert_true(_rows()[0].find_child("Update", true, false) != null)
	assert_true(_rows()[1].find_child("Update", true, false) == null, "fijado: sin botón Actualizar")
	assert_eq((_rows()[2].find_child("UpdateNote", true, false) as Label).text, "v3.0.0 pide Godot 4.6+")


func test_presets_menu() -> void:
	var p := PluginPreset.new()
	p.name = "mios"
	p.plugins.append({"name": "a", "source": "store:x/a", "version": ""})
	dialog.show_presets([p])
	var menu := (dialog.get_node("%Presets") as MenuButton).get_popup()
	assert_eq(menu.get_item_text(0), "Aplicar «mios»")
	assert_eq(menu.get_item_text(menu.item_count - 1), "Guardar como preset…")


func test_save_preset_and_pending_with_cli() -> void:
	if not _setup_cli():
		return
	if not fx.setup():
		fail(fx.last_error)
		return
	_write("plugins.json", '{"plugins": {"later": {"source": "github:a/later"}}}')
	dialog.fill(ProjectEntry.read(project_dir), null)
	await dialog.load_plugins()
	var pending: Array = dialog.plugins.filter(func(p: ProjectPlugin) -> bool: return p.pending)
	assert_eq(pending.size(), 1)
	var job: CliJob = await dialog.save_preset("mios", false)
	assert_true(job.succeeded(), job.stdout + job.stderr)
	assert_eq(_status(), "Se guardó el preset «mios».")
	await dialog.load_presets()
	assert_eq(dialog.presets.size(), 1)
	assert_eq(dialog.presets[0].summary(), "later")
	fx.teardown()
