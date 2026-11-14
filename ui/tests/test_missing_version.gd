extends TestCase
## Proyecto con una versión no instalada: el diálogo (instalar, otra, la
## default), qué argumentos usa "la default" y, contra el CLI real (GM_BIN),
## que elegir la default quita el .godot-version.

const DIALOG := preload("res://dialogs/missing_version_dialog.tscn")
const SCREEN := preload("res://screens/projects_screen.tscn")
const ProjectsScreen := preload("res://screens/projects_screen.gd")
const CFG := "user://test_missing_version.cfg"

var dialog: AcceptDialog
var fx: CliFixture
var screen: Control
var _old_binary := ""
var _old_available := false


func before_each() -> void:
	dialog = DIALOG.instantiate()
	tree.root.add_child(dialog)


func after_each() -> void:
	dialog.queue_free()
	if screen != null:
		screen.queue_free()
		screen = null
	if fx != null and fx.available() and not fx.root.is_empty():
		GmCli.binary = _old_binary
		GmCli.available = _old_available
		fx.teardown()
	fx = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	await wait_frames(1)


func _buttons() -> Dictionary:
	var out := {}
	for b in dialog.find_children("*", "Button", true, false):
		out[(b as Button).text] = b
	return out


func test_dialog_pinned() -> void:
	dialog.fill("Mi Juego", "4.3-stable", "4.7.2-stable", 2)
	assert_eq((dialog.get_node("%Message") as Label).text, "«Mi Juego» está fijado a 4.3-stable, que no está instalada.")
	assert_eq(dialog.get_ok_button().text, "Instalar 4.3-stable")
	var b := _buttons()
	assert_has(b, "Usar la default (4.7.2-stable)")
	assert_false((b["Elegir otra versión…"] as Button).disabled)


func test_dialog_without_others_or_default() -> void:
	dialog.fill("Mi Juego", "4.3-stable", "", 0)
	var b := _buttons()
	assert_true((b["Elegir otra versión…"] as Button).disabled)
	assert_true((b["Usar la default"] as Button).disabled)


func test_dialog_missing_default_hides_default() -> void:
	dialog.fill("Mi Juego", "4.5-stable", "", 1, true)
	assert_eq((dialog.get_node("%Message") as Label).text, "«Mi Juego» usa la versión default, 4.5-stable, que no está instalada.")
	var hidden := false
	for b in dialog.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with("Usar la default"):
			hidden = not (b as Button).visible
	assert_true(hidden)


func test_choice_signal() -> void:
	var got: Array[StringName] = []
	dialog.choice.connect(func(k: StringName) -> void: got.append(k))
	dialog.fill("p", "4.3-stable", "4.7.2-stable", 1)
	dialog.custom_action.emit(&"other")
	dialog.confirmed.emit()
	assert_eq(got, [&"other", &"install"] as Array[StringName])


func _status(source: String) -> ProjectStatus:
	var s := ProjectStatus.new()
	s.state = ProjectStatus.State.NOT_INSTALLED
	s.error = CliError.make("not_installed", "x", {"version": "4.3-stable", "source": source})
	return s


func test_default_args() -> void:
	var e := ProjectEntry.new()
	e.path = "/home/u/juego"
	assert_eq(ProjectsScreen.default_args(e, _status("/home/u/juego/.godot-version"), "4.7"),
		GmCommands.unset_local("/home/u/juego"), "su propio .godot-version se borra")
	assert_eq(ProjectsScreen.default_args(e, _status("/home/u/.godot-version"), "4.7"),
		GmCommands.set_local("/home/u/juego", "4.7"), "si viene de más arriba, se fija la default")


func test_use_default_with_cli() -> void:
	fx = CliFixture.new()
	if not fx.available():
		skip(fx.why_unavailable())
		return
	fx.setup(["4.2-fake"])
	fx.run(GmCommands.set_default("4.2-fake"))
	_old_binary = GmCli.binary
	_old_available = GmCli.available
	GmCli.binary = fx.gm_bin
	GmCli.available = true
	var project := fx.root.path_join("juego")
	DirAccess.make_dir_recursive_absolute(project)
	var f := FileAccess.open(project.path_join("project.godot"), FileAccess.WRITE)
	f.store_string("config_version=5\n\n[application]\n\nconfig/name=\"Juego\"\n")
	f.close()
	f = FileAccess.open(project.path_join(".godot-version"), FileAccess.WRITE)
	f.store_string("9.9-falta\n")
	f.close()

	screen = SCREEN.instantiate()
	screen.list_path = CFG
	tree.root.add_child(screen)
	screen.add_project(project)
	await wait_until(func() -> bool: return not screen.is_resolving(), 5.0)
	var st: ProjectStatus = screen.statuses[ProjectEntry.normalize(project)]
	assert_eq(st.missing_version(), "9.9-falta")

	var e: ProjectEntry = screen.entries[0]
	await screen.ask_missing(e)
	var d: AcceptDialog = screen.get_node("%MissingVersionDialog")
	assert_true(d.visible)
	assert_eq(screen._missing_default, "4.2-fake")
	d.hide()
	screen._on_missing_choice(&"default")
	await wait_until(func() -> bool: return not FileAccess.file_exists(project.path_join(".godot-version")), 5.0)
	assert_false(FileAccess.file_exists(project.path_join(".godot-version")), "se quitó el .godot-version")
	await wait_until(func() -> bool:
		var s: ProjectStatus = screen.statuses[ProjectEntry.normalize(project)]
		return s.state == ProjectStatus.State.DEFAULT, 5.0)
	assert_eq((screen.statuses[ProjectEntry.normalize(project)] as ProjectStatus).state, ProjectStatus.State.DEFAULT)
