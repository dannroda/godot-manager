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
	dialog.naming = DirNaming.Convention.KEBAB
	dialog.get_node("%ProjectName").text = "Mi juego"
	assert_true(dialog._validate())
	assert_eq(_target(), "Se crea en %s" % root.path_join("mi-juego"), "la carpeta en kebab-case, como Godot")
	assert_eq(dialog.command(), GmCommands.new_project(root.path_join("mi-juego"), "Mi juego"))
	dialog.naming = DirNaming.Convention.NONE
	assert_eq(dialog.target_path(), root.path_join("Mi juego"))
	dialog.naming = DirNaming.Convention.KEBAB
	version.select(1)
	(dialog.get_node("%Renderer") as OptionButton).select(2)
	var preset := PluginPreset.new()
	preset.name = "mios"
	dialog.show_presets([preset])
	(dialog.get_node("%Preset") as OptionButton).select(1)
	assert_eq(dialog.command(), GmCommands.new_project(root.path_join("mi-juego"), "Mi juego", "4.5.1-stable", "gl_compatibility", "mios"))
	DirAccess.make_dir_recursive_absolute(root.path_join("mi-juego"))
	FileAccess.open(root.path_join("mi-juego/x.txt"), FileAccess.WRITE).store_string("x")
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
	assert_true(FileAccess.file_exists(path.path_join("icon.svg")), "con el ícono de Godot, como el Project Manager")
	var names: PackedStringArray = []
	for e: ProjectEntry in screen.visible_projects():
		names.append(e.name)
	assert_has(names, "Nuevo")


func test_dir_naming() -> void:
	assert_eq(DirNaming.dir_name("ChronoWar"), "chrono-war", "kebab-case por defecto, como Godot")
	assert_eq(DirNaming.dir_name("Mi Juego 2"), DirNaming.dir_name("Mi Juego 2", DirNaming.Convention.KEBAB))
	assert_eq(DirNaming.dir_name("Mi Juego", DirNaming.Convention.SNAKE), "mi_juego")
	assert_eq(DirNaming.dir_name("Mi Juego", DirNaming.Convention.PASCAL), "MiJuego")
	assert_eq(DirNaming.dir_name("Mi Juego", DirNaming.Convention.CAMEL), "miJuego")
	assert_eq(DirNaming.dir_name("¿Qué? <x>", DirNaming.Convention.NONE), "¿Qué- -x-")
	assert_eq(DirNaming.dir_name("Fin...", DirNaming.Convention.NONE), "Fin")
	assert_eq(DirNaming.dir_name("..", DirNaming.Convention.NONE), "twodots")


func test_read_convention() -> void:
	var dir := root.path_join("config")
	DirAccess.make_dir_recursive_absolute(dir)
	assert_eq(DirNaming.read_convention(dir), DirNaming.Convention.KEBAB, "sin ajustes: la default de Godot")
	var write := func(file: String, text: String) -> void:
		FileAccess.open(dir.path_join(file), FileAccess.WRITE).store_string(text)
	write.call("editor_settings-4.7.tres", "[resource]\nproject_manager/directory_naming_convention = 4\n")
	write.call("editor_settings-4.10.tres", "[gd_resource type=\"EditorSettings\" format=3]\n\n[resource]\nproject_manager/directory_naming_convention = 2\n")
	assert_eq(DirNaming.read_convention(dir), DirNaming.Convention.SNAKE, "el de la versión más nueva (4.10 > 4.7)")
	write.call("editor_settings-4.10.tres", "[resource]\ninterface/editor/x = 1\n")
	assert_eq(DirNaming.read_convention(dir), DirNaming.Convention.KEBAB, "sin el ajuste: la default")
