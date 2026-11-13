extends TestCase
## Versión que usa cada proyecto: ProjectStatus desde la salida de `which`
## (unidad) y la pestaña Proyectos contra el CLI real (integración, GM_BIN).

const SCREEN := preload("res://screens/projects_screen.tscn")
const CFG := "user://test_project_status.cfg"
const OUTPUT := preload("res://panels/output_panel.tscn")


static func _job(code: int, out: String) -> CliJob:
	var j := CliJob.new(["--json", "which"], CliJob.Kind.READ)
	j.exit_code = code
	j.stdout = out
	j.state = CliJob.State.DONE
	return j


func test_pinned() -> void:
	var s := ProjectStatus.from_job(_job(0, FileAccess.get_file_as_string("res://tests/fixtures/which.json")))
	assert_eq(s.state, ProjectStatus.State.PINNED)
	assert_eq(s.text(), "4.8-beta3 · fijada")
	assert_has(s.tooltip(), ".godot-version")
	assert_false(s.is_error())
	assert_eq(s.missing_version(), "")


func test_default() -> void:
	var s := ProjectStatus.from_job(_job(0, '{"path":"/v/4.7/godot","version":"4.7.2-stable","source":"default"}'))
	assert_eq(s.state, ProjectStatus.State.DEFAULT)
	assert_eq(s.text(), "4.7.2-stable · default")


func test_not_installed_uses_version_field() -> void:
	var s := ProjectStatus.from_job(_job(1,
		'{"error":{"code":"not_installed","message":"\'9.9-nope\' (de /p/.godot-version) no esta instalada","version":"9.9-nope","source":"/p/.godot-version"}}'))
	assert_eq(s.state, ProjectStatus.State.NOT_INSTALLED)
	assert_true(s.is_error())
	assert_eq(s.missing_version(), "9.9-nope")
	assert_eq(s.text(), "9.9-nope no instalada")
	assert_eq(s.tooltip(), "'9.9-nope' (de /p/.godot-version) no esta instalada", "el mensaje del CLI tal cual")


func test_other_errors() -> void:
	var s := ProjectStatus.from_job(_job(1, '{"error":{"code":"no_default","message":"no hay version por defecto"}}'))
	assert_eq(s.state, ProjectStatus.State.ERROR)
	assert_eq(s.text(), "Sin versión por defecto")
	assert_eq(s.tooltip(), "no hay version por defecto")
	assert_eq(s.missing_version(), "", "sin botón Instalar")
	var bad := ProjectStatus.from_job(_job(0, "basura"))
	assert_eq(bad.state, ProjectStatus.State.ERROR)
	assert_eq(bad.error.code, CliError.BAD_OUTPUT)
	var pending := ProjectStatus.pending()
	assert_eq(pending.text(), "…")


# --- Integración --------------------------------------------------------------

var fx: CliFixture
var _old_binary := ""
var _old_available := false


func _setup_cli() -> bool:
	fx = CliFixture.new()
	if not fx.available():
		skip(fx.why_unavailable())
		return false
	if not fx.setup(["4.2-fake", "4.3-fake"]):
		fail(fx.last_error)
		return false
	fx.run(GmCommands.set_default("4.3-fake"))
	_old_binary = GmCli.binary
	_old_available = GmCli.available
	GmCli.binary = fx.gm_bin
	GmCli.available = true
	return true


func _teardown_cli() -> void:
	GmCli.binary = _old_binary
	GmCli.available = _old_available
	fx.teardown()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))


func _project(dir: String, pinned := "") -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("project.godot"), FileAccess.WRITE)
	f.store_string("config_version=5\n")
	f.close()
	if not pinned.is_empty():
		var g := FileAccess.open(dir.path_join(".godot-version"), FileAccess.WRITE)
		g.store_string(pinned + "\n")
		g.close()
	return dir


func _row(screen: Control, path: String) -> Control:
	for row in screen.get_node("%Rows").get_children():
		if row.project.path == path:
			return row
	return null


## Abrir (3.3) con versiones falsas (/bin/true): fijada, default y no instalada.
func test_open_three_cases() -> void:
	if not _setup_cli():
		return
	var pinned := _project(fx.root.path_join("fijada"), "4.2-fake")
	var plain := _project(fx.root.path_join("sin archivo"))
	var missing := _project(fx.root.path_join("falta"), "9.9-nope")
	var screen := SCREEN.instantiate()
	screen.list_path = CFG
	tree.root.add_child(screen)
	var errors: Array[String] = []
	screen.error_reported.connect(func(m: String) -> void: errors.append(m))
	for p in [pinned, plain, missing]:
		screen.add_project(p)
	var status: Label = screen.get_node("%Status")

	screen._select_path(pinned)
	assert_false((screen.get_node("%Open") as Button).disabled)
	var job: CliJob = await screen.open_selected(true)
	assert_eq(job.args, PackedStringArray(["--json", "--dir", pinned, "run", "--detach", "-e"]))
	assert_true(job.succeeded(), job.stdout)
	assert_eq(status.text, "Se abrió «fijada» con 4.2-fake.")

	screen._select_path(plain)
	job = await screen.open_selected(false)
	assert_eq(job.args, PackedStringArray(["--json", "--dir", plain, "run", "--detach"]), "Correr: sin -e")
	assert_eq(status.text, "Se corrió «sin archivo» con 4.3-fake.")

	screen._select_path(missing)
	job = await screen.open_selected(true)
	assert_false(job.succeeded())
	var dialog: ConfirmationDialog = screen.get_node("%InstallDialog")
	assert_true(dialog.visible, "ofrece instalar")
	assert_eq(dialog.options.version, "9.9-nope")
	assert_eq(screen.statuses[missing].state, ProjectStatus.State.NOT_INSTALLED)
	assert_eq(errors.size(), 0, "not_installed no es un aviso de error")
	dialog.hide()
	screen.queue_free()
	await wait_frames(1)
	_teardown_cli()


func test_screen_three_projects() -> void:
	if not _setup_cli():
		return
	var pinned := _project(fx.root.path_join("fijada"), "4.2-fake")
	var plain := _project(fx.root.path_join("sin archivo"))
	var missing := _project(fx.root.path_join("falta"), "9.9-nope")
	var l := ProjectList.new()
	l.add_all(PackedStringArray([pinned, plain, missing, fx.root.path_join("borrado")]))
	l.save(CFG)

	var output: Control = OUTPUT.instantiate()
	tree.root.add_child(output)
	var screen := SCREEN.instantiate()
	screen.list_path = CFG
	tree.root.add_child(screen)
	for i in 300:
		if not screen.is_resolving():
			break
		await wait_frames(1)
	assert_false(screen.is_resolving())
	assert_eq(output.plain_text(), "", "un which con not_installed no ensucia Salida (la fila ya lo muestra)")
	output.queue_free()
	assert_eq(screen.statuses[pinned].text(), "4.2-fake · fijada")
	assert_eq(screen.statuses[plain].text(), "4.3-fake · default")
	assert_eq(screen.statuses[missing].text(), "9.9-nope no instalada")
	assert_false(screen.statuses.has(fx.root.path_join("borrado")), "a los que faltan no se les pregunta")
	var row := _row(screen, missing)
	assert_true((row.get_node("%Install") as Button).visible)
	assert_true((row.get_node("%Uses") as Label).visible)
	assert_false((_row(screen, pinned).get_node("%Install") as Button).visible)
	assert_eq(GmCli.history.filter(func(j: CliJob) -> bool: return j.background).size(), 0,
		"los which de fondo no van al historial")

	# Instalar… abre el diálogo de 2.2 con ese tag.
	(row.get_node("%Install") as Button).pressed.emit()
	var dialog: ConfirmationDialog = screen.get_node("%InstallDialog")
	assert_true(dialog.visible)
	assert_eq(dialog.options.version, "9.9-nope")
	dialog.hide()

	# Cambiar la default se ve en la fila sin .godot-version.
	var job := GmCli.write(GmCommands.set_default("4.2-fake"))
	await job.finished
	await wait_frames(1)  # versions_changed sale después de finished.
	assert_true(screen.is_resolving(), "cambiar la default vuelve a preguntar")
	for i in 300:
		if not screen.is_resolving():
			break
		await wait_frames(1)
	assert_eq(screen.statuses[plain].text(), "4.2-fake · default")
	screen.queue_free()
	await wait_frames(1)
	_teardown_cli()
