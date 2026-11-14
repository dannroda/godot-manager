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
