extends TestCase
## Cambiar versión (3.4): selector, aviso de versión vieja, comando, y la
## escritura real con `set-local --dir` (integración, GM_BIN).

const DIALOG := preload("res://dialogs/change_version_dialog.tscn")
const SCREEN := preload("res://screens/projects_screen.tscn")
const CFG := "user://test_change_version.cfg"

var dialog: ConfirmationDialog


func before_each() -> void:
	dialog = DIALOG.instantiate()
	tree.root.add_child(dialog)


func after_each() -> void:
	dialog.queue_free()
	await wait_frames(1)


func _v(n: String, tag := "", is_default := false) -> InstalledVersion:
	var v := InstalledVersion.new()
	v.name = n
	v.tag = tag
	v.path = "/opt/godot/versions/%s/godot" % n
	v.is_default = is_default
	return v


func _versions() -> Array[InstalledVersion]:
	return [_v("4.7.2-stable", "4.7.2-stable", true), _v("4.8-beta3", "4.8-beta3"), _v("mi-build", "", false)]


func _project(features := "4.8") -> ProjectEntry:
	var p := ProjectEntry.new()
	p.path = "/home/u/mi juego"
	p.name = "Mi Juego"
	p.features = PackedStringArray([features])
	return p


func _status(state: ProjectStatus.State, version := "") -> ProjectStatus:
	var s := ProjectStatus.new()
	s.state = state
	if state == ProjectStatus.State.PINNED or state == ProjectStatus.State.DEFAULT:
		s.resolution = Resolution.new()
		s.resolution.version = version
		s.resolution.source = "default" if state == ProjectStatus.State.DEFAULT else "/x/.godot-version"
	return s


func _list() -> ItemList:
	return dialog.get_node("%Versions")


func _texts() -> PackedStringArray:
	var out := PackedStringArray()
	for i in _list().item_count:
		out.append(_list().get_item_text(i))
	return out


func _pick(i: int) -> void:
	_list().select(i)
	_list().item_selected.emit(i)


func test_current_pinned_is_marked_and_selected() -> void:
	dialog.fill(_project(), _versions(), _status(ProjectStatus.State.PINNED, "4.8-beta3"))
	assert_eq(_texts(), PackedStringArray(["Usar la default (4.7.2-stable)", "4.8-beta3 · actual",
		"4.7.2-stable", "mi-build"]), "más nueva arriba; la actual marcada")
	assert_eq(dialog.chosen().name, "4.8-beta3")
	assert_true(dialog.get_ok_button().disabled, "sin cambios no hay nada que correr")
	_pick(0)
	assert_eq(dialog.command(), PackedStringArray(["--json", "--dir", "/home/u/mi juego", "set-local", "--unset"]))
	assert_false(dialog.get_ok_button().disabled)


func test_default_project() -> void:
	dialog.fill(_project(), _versions(), _status(ProjectStatus.State.DEFAULT, "4.7.2-stable"))
	assert_eq(_texts()[0], "Usar la default (4.7.2-stable) · actual")
	assert_eq(dialog.chosen(), null)
	assert_eq(dialog.command(), PackedStringArray(), "ya usa la default: --unset no cambia nada")
	_pick(1)
	assert_eq(dialog.command(), PackedStringArray(["--json", "--dir", "/home/u/mi juego", "set-local", "4.8-beta3"]))
	# En Windows con comillas dobles, para pegarlo en cmd o PowerShell.
	var quoted := "\"/home/u/mi juego\"" if OS.get_name() == "Windows" else "'/home/u/mi juego'"
	assert_eq((dialog.get_node("%Command") as Label).text,
		"godot-manager --json --dir %s set-local 4.8-beta3" % quoted)


func test_older_than_project_warns() -> void:
	dialog.fill(_project("4.8"), _versions(), _status(ProjectStatus.State.PINNED, "4.8-beta3"))
	var warning: Label = dialog.get_node("%Warning")
	assert_false(warning.visible)
	_pick(2)
	assert_true(warning.visible, "4.7.2 es más vieja que 4.8")
	assert_has(warning.text, "4.8")
	_pick(3)
	assert_false(warning.visible, "un build sin número no avisa")
	assert_false(dialog.older_than_project(_v("4.8-beta1", "4.8-beta1"), _project("4.8")), "misma 4.8")
	assert_true(dialog.older_than_project(_v("3.6-stable", "3.6-stable"), _project("4.2")))
	assert_false(dialog.older_than_project(_v("4.2-stable", "4.2-stable"), _project("3.x")))


func test_not_installed_pinned_counts_as_current() -> void:
	var s := ProjectStatus.new()
	s.state = ProjectStatus.State.NOT_INSTALLED
	s.error = CliError.make("not_installed", "m", {"version": "4.8-dev6"})
	dialog.fill(_project(), _versions(), s)
	assert_eq(dialog.chosen(), null, "la fijada no está en la lista")
	assert_eq(dialog.command(), PackedStringArray(["--json", "--dir", "/home/u/mi juego", "set-local", "--unset"]),
		"usar la default quita el archivo que apunta a la que falta")


func test_confirm_emits() -> void:
	var got: Array = []
	dialog.change_requested.connect(func(a: PackedStringArray) -> void: got.append(a))
	dialog.fill(_project(), _versions(), _status(ProjectStatus.State.DEFAULT, "4.7.2-stable"))
	_pick(1)
	dialog.confirmed.emit()
	assert_eq(got.size(), 1)
	assert_eq(got[0][-1], "4.8-beta3")


# --- Integración --------------------------------------------------------------

func test_set_local_through_screen() -> void:
	var fx := CliFixture.new()
	if not fx.available():
		skip(fx.why_unavailable())
		return
	if not assert_true(fx.setup(["4.2-fake", "4.3-fake"]), fx.last_error):
		fx.teardown()
		return
	fx.run(GmCommands.set_default("4.3-fake"))
	var old_binary := GmCli.binary
	var old_available := GmCli.available
	GmCli.binary = fx.gm_bin
	GmCli.available = true
	var dir := fx.root.path_join("proyecto")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("project.godot"), FileAccess.WRITE)
	f.store_string("config_version=5\n")
	f.close()

	var screen := SCREEN.instantiate()
	screen.list_path = CFG
	tree.root.add_child(screen)
	screen.add_project(dir)
	await _settle(screen)
	assert_eq(screen.statuses[dir].text(), "4.3-fake · default")

	var job: CliJob = await screen.change_version(GmCommands.set_local(dir, "4.2-fake"))
	assert_true(job.succeeded(), job.stdout)
	assert_true(FileAccess.file_exists(dir.path_join(".godot-version")), "lo escribió el CLI")
	await _settle(screen)
	assert_eq(screen.statuses[dir].text(), "4.2-fake · fijada", "la fila se actualiza sola")
	assert_eq((screen.get_node("%Status") as Label).text, "Listo: «proyecto» usa 4.2-fake.")

	job = await screen.change_version(GmCommands.unset_local(dir))
	assert_true(job.succeeded(), job.stdout)
	assert_false(FileAccess.file_exists(dir.path_join(".godot-version")), "usar la default lo quita")
	await _settle(screen)
	assert_eq(screen.statuses[dir].text(), "4.3-fake · default")

	screen.queue_free()
	await wait_frames(1)
	GmCli.binary = old_binary
	GmCli.available = old_available
	fx.teardown()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))


func _settle(screen: Control) -> void:
	await wait_frames(1)
	for i in 300:
		if not screen.is_resolving():
			return
		await wait_frames(1)
