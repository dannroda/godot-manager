extends TestCase
## Proyecto nuevo: el diálogo (validación, argumentos de `new`) y, contra el CLI
## real (GM_BIN), crearlo desde la pantalla de proyectos y que quede en la lista.

const DIALOG := preload("res://dialogs/new_project_dialog.tscn")
const SCREEN := preload("res://screens/projects_screen.tscn")
const CFG := "user://test_new_project.cfg"

var dialog: ConfirmationDialog
var screen: Control
var root := ""
var fx: CliFixture
var _old_binary := ""
var _old_available := false


func before_each() -> void:
	root = ProjectSettings.globalize_path("user://test_new_project_tree")
	CliFixture._remove_tree(root)
	DirAccess.make_dir_recursive_absolute(root)
	dialog = DIALOG.instantiate()
	tree.root.add_child(dialog)
	_old_binary = GmCli.binary
	_old_available = GmCli.available


func after_each() -> void:
	GmCli.binary = _old_binary
	GmCli.available = _old_available
	dialog.queue_free()
	if screen != null:
		screen.queue_free()
		screen = null
	if fx != null:
		fx.teardown()
		fx = null
	await wait_frames(1)
	CliFixture._remove_tree(root)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))


func _version(name: String, tag: String, is_default := false, custom := false) -> InstalledVersion:
	var v := InstalledVersion.new()
	v.name = name
	v.tag = tag
	v.is_default = is_default
	v.custom = custom
	return v


func _target() -> String:
	return (dialog.get_node("%Target") as Label).text


func test_validation_and_command() -> void:
	dialog.get_node("%ParentDir").text = root
	dialog.show_versions([_version("4.5.1-stable", "4.5.1-stable", true), _version("3.6-stable", "3.6-stable"),
		_version("mio", "", false, true)])
	var version: OptionButton = dialog.get_node("%Version")
	assert_eq(version.get_item_text(0), "La default (4.5.1-stable)")
	assert_eq(version.item_count, 3, "sin la 3.6")
	assert_false(dialog._validate(), "sin nombre")
	assert_eq(_target(), "Poné un nombre.")
	dialog.get_node("%ProjectName").text = "Mi juego"
	assert_true(dialog._validate())
	assert_eq(_target(), "Se crea en %s" % root.path_join("Mi juego"))
	assert_eq(dialog.command(), GmCommands.new_project(root.path_join("Mi juego"), "Mi juego"))
	version.select(1)
	(dialog.get_node("%Renderer") as OptionButton).select(2)
	var preset := PluginPreset.new()
	preset.name = "mios"
	dialog.show_presets([preset])
	(dialog.get_node("%Preset") as OptionButton).select(1)
	assert_eq(dialog.command(), GmCommands.new_project(root.path_join("Mi juego"), "Mi juego", "4.5.1-stable", "gl_compatibility", "mios"))
	DirAccess.make_dir_recursive_absolute(root.path_join("Mi juego"))
	FileAccess.open(root.path_join("Mi juego/x.txt"), FileAccess.WRITE).store_string("x")
	assert_false(dialog._validate(), "carpeta con archivos")


func test_create_with_cli() -> void:
	fx = CliFixture.new()
	if not fx.available():
		skip(fx.why_unavailable())
		return
	if not fx.setup():
		fail(fx.last_error)
		return
	GmCli.binary = fx.gm_bin
	GmCli.available = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	screen = SCREEN.instantiate()
	screen.list_path = CFG
	tree.root.add_child(screen)
	var path := root.path_join("Nuevo")
	var job: CliJob = await screen.create_project(GmCommands.new_project(path, "Nuevo", "", "mobile"), path)
	assert_true(job.succeeded(), job.stdout + job.stderr)
	assert_true(FileAccess.get_file_as_string(path.path_join("project.godot")).contains("config/name=\"Nuevo\""))
	var names: PackedStringArray = []
	for e: ProjectEntry in screen.visible_projects():
		names.append(e.name)
	assert_has(names, "Nuevo")
