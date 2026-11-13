extends TestCase

const GmCliScript := preload("res://cli/gm_cli.gd")
const TMP := "user://test_settings.cfg"


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func test_defaults_when_missing() -> void:
	var s := AppSettings.load_from("user://no_existe_123.cfg")
	assert_eq(s.binary_mode, AppSettings.BinaryMode.SEARCH_PATH)
	assert_eq(s.binary(), "godot-manager")
	assert_eq(s.cli_env(), {"GITHUB_TOKEN": "", "GODOT_DIR": ""})


func test_save_and_load_roundtrip() -> void:
	var s := AppSettings.new()
	s.binary_mode = AppSettings.BinaryMode.FIXED
	s.binary_path = "/opt/mi gm/godot-manager"
	s.github_token = "ghp_secreto"
	s.godot_dir = "/tmp/godot dir"
	assert_eq(s.save(TMP), OK)
	var l := AppSettings.load_from(TMP)
	assert_eq(l.binary_mode, AppSettings.BinaryMode.FIXED)
	assert_eq(l.binary(), "/opt/mi gm/godot-manager")
	assert_eq(l.cli_env(), {"GITHUB_TOKEN": "ghp_secreto", "GODOT_DIR": "/tmp/godot dir"})


func test_fixed_without_path_falls_back_to_path_search() -> void:
	var s := AppSettings.new()
	s.binary_mode = AppSettings.BinaryMode.FIXED
	s.binary_path = "  "
	assert_eq(s.binary(), "godot-manager")


func test_broken_file_gives_defaults() -> void:
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("[cli\nbinary_mode = = =")
	f.close()
	var s := AppSettings.load_from(TMP)
	assert_eq(s.binary(), "godot-manager")


func test_settings_reach_child_env() -> void:
	var bin := OS.get_environment("GM_BIN")
	if bin.is_empty():
		skip("falta GM_BIN (ruta a godot-manager)")
		return
	var fx := CliFixture.new()
	if not assert_true(fx.setup(["7.7-fake"]), fx.last_error):
		fx.teardown()
		return
	var root := fx.root
	# Sacar GODOT_DIR del entorno sin borrar la carpeta: tiene que llegar por Ajustes.
	OS.unset_environment("GODOT_DIR")

	var cli: Node = GmCliScript.new()
	tree.root.add_child(cli)
	var s := AppSettings.new()
	s.binary_mode = AppSettings.BinaryMode.FIXED
	s.binary_path = bin
	s.godot_dir = root
	s.github_token = "ghp_prueba"
	s.apply_to(cli)
	assert_eq(cli.binary, bin)
	var job: CliJob = cli.read(GmCommands.list())
	await job.finished
	var r := GmParse.parse_list(job.stdout)
	if assert_true(r.ok, str(r.error)):
		assert_eq((r.value[0] as InstalledVersion).name, "7.7-fake")
	assert_eq(OS.get_environment("GITHUB_TOKEN"), "ghp_prueba", "el token queda en el entorno del hijo")
	s.github_token = ""
	s.godot_dir = ""
	s.apply_to(cli)
	var job2: CliJob = cli.read(GmCommands.cli_version())
	await job2.finished
	assert_false(OS.has_environment("GITHUB_TOKEN"), "vaciar el token lo saca del entorno")
	cli.queue_free()
	OS.set_environment("GODOT_DIR", root)
	fx.teardown()


func test_cli_version_parsing() -> void:
	var ok := _job(0, "2.1.0\n")
	assert_eq(GmParse.parse_cli_version(ok).value, "2.1.0")
	var old := _job(0, "1.9.0\n")
	var r_old := GmParse.parse_cli_version(old)
	assert_eq(r_old.error.code, GmParse.OLD_CLI)
	assert_has(r_old.error.message, "1.9.0")
	var bash := _job(1, "", "Uso: godot-manager {list|install|set} ...\n")
	var r_bash := GmParse.parse_cli_version(bash)
	assert_eq(r_bash.error.code, GmParse.OLD_CLI)
	assert_has(r_bash.error.message, "1.x")
	assert_has(r_bash.error.message, "Uso: godot-manager", "muestra la salida tal cual")
	var usage_exit0 := _job(0, "Uso: godot-manager ...\n")
	assert_eq(GmParse.parse_cli_version(usage_exit0).error.code, GmParse.OLD_CLI)


func test_probe_binaries() -> void:
	var cli: Node = GmCliScript.new()
	tree.root.add_child(cli)
	var missing: GmResult = await cli.probe("/no/existe/gm")
	assert_eq(missing.error.code, CliError.NO_BINARY)
	assert_has(missing.error.message, "/no/existe/gm")
	if OS.get_name() != "Windows":
		var wrong: GmResult = await cli.probe("/bin/false")
		assert_eq(wrong.error.code, GmParse.OLD_CLI)
	var bin := OS.get_environment("GM_BIN")
	if not bin.is_empty():
		cli.binary = bin
		var r: GmResult = await cli.check()
		assert_true(r.ok, str(r.error))
		assert_true(cli.available)
		cli.binary = "/no/existe/gm"
		await cli.check()
		assert_false(cli.available)
		assert_has(cli.availability_message, "No se encontró")
	cli.queue_free()


static func _job(code: int, out: String, err := "") -> CliJob:
	var j := CliJob.new(GmCommands.cli_version(), CliJob.Kind.READ)
	j.exit_code = code
	j.stdout = out
	j.stderr = err
	j.state = CliJob.State.DONE
	return j
