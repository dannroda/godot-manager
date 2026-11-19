extends TestCase
## Integración: GmCommands + GmParse contra el CLI real (GM_BIN) en un
## GODOT_DIR temporal. Sin red.

var fx: CliFixture


func before_each() -> void:
	fx = CliFixture.new()
	if not fx.available():
		skip(fx.why_unavailable())
		return
	if not fx.setup(["4.2-fake", "4.3-fake"]):
		fail(fx.last_error)


func after_each() -> void:
	if fx != null:
		fx.teardown()


func test_list_parses() -> void:
	var r := GmParse.parse_list(fx.run(GmCommands.list())["stdout"])
	if not assert_true(r.ok, str(r.error)):
		return
	var v: InstalledVersion = r.value[0]
	assert_eq(v.name, "4.2-fake")
	assert_true(v.custom)
	assert_false(v.is_default)


func test_set_default_then_list() -> void:
	var s := GmParse.parse_ok(fx.run(GmCommands.set_default("4.3-fake"))["stdout"])
	if not assert_true(s.ok, str(s.error)):
		return
	assert_eq(s.value["version"], "4.3-fake")
	var r := GmParse.parse_list(fx.run(GmCommands.list())["stdout"])
	assert_true((r.value[1] as InstalledVersion).is_default)


func test_which_without_default_is_cli_error() -> void:
	var out := fx.run(GmCommands.which(fx.root))
	assert_eq(out["exit"], 1)
	var r := GmParse.parse_which(out["stdout"])
	assert_false(r.ok)
	assert_eq(r.error.code, "no_default")


func test_set_local_and_which_in_folder_with_spaces() -> void:
	var project := fx.root.path_join("mi proyecto")
	DirAccess.make_dir_recursive_absolute(project)
	var s := GmParse.parse_ok(fx.run(GmCommands.set_local(project, "4.2-fake"))["stdout"])
	if not assert_true(s.ok, str(s.error)):
		return
	var w := GmParse.parse_which(fx.run(GmCommands.which(project))["stdout"])
	if assert_true(w.ok, str(w.error)):
		assert_eq((w.value as Resolution).version, "4.2-fake")
		assert_true((w.value as Resolution).source.ends_with(".godot-version"))
	var u := GmParse.parse_ok(fx.run(GmCommands.unset_local(project))["stdout"])
	assert_true(u.ok, str(u.error))


## Los tres casos de la fila de un proyecto (3.2): fijada e instalada, sin
## .godot-version (la default) y fijada a una que no está instalada.
func test_which_dir_three_cases() -> void:
	fx.run(GmCommands.set_default("4.3-fake"))
	var pinned := fx.root.path_join("fijada")
	var plain := fx.root.path_join("sin archivo")
	var missing := fx.root.path_join("falta")
	for d in [pinned, plain, missing]:
		DirAccess.make_dir_recursive_absolute(d)
	fx.run(GmCommands.set_local(pinned, "4.2-fake"))
	var f := FileAccess.open(missing.path_join(".godot-version"), FileAccess.WRITE)
	f.store_string("9.9-nope\n")
	f.close()

	var a := GmParse.parse_which(fx.run(GmCommands.which(pinned))["stdout"])
	if assert_true(a.ok, str(a.error)):
		assert_eq((a.value as Resolution).version, "4.2-fake")
		assert_false((a.value as Resolution).is_from_default())
	var b := GmParse.parse_which(fx.run(GmCommands.which(plain))["stdout"])
	if assert_true(b.ok, str(b.error)):
		assert_eq((b.value as Resolution).version, "4.3-fake")
		assert_true((b.value as Resolution).is_from_default())
	var out := fx.run(GmCommands.which(missing))
	assert_eq(out["exit"], 1)
	var c := GmParse.parse_which(out["stdout"])
	assert_false(c.ok)
	assert_eq(c.error.code, "not_installed")
	assert_eq(c.error.extra.get("version"), "9.9-nope", "trae la versión para el botón Instalar")
	assert_true(str(c.error.extra.get("source")).ends_with(".godot-version"))
	var gone := GmParse.parse_which(fx.run(GmCommands.which(fx.root.path_join("no existe")))["stdout"])
	assert_false(gone.ok, "carpeta inexistente: error del CLI")
	print("    which en carpeta inexistente: ", gone.error)


func test_remove() -> void:
	var r := GmParse.parse_ok(fx.run(GmCommands.remove("4.2-fake"))["stdout"])
	if not assert_true(r.ok, str(r.error)):
		return
	assert_eq(r.value["version"], "4.2-fake")
	var l := GmParse.parse_list(fx.run(GmCommands.list())["stdout"])
	assert_eq((l.value as Array).size(), 1)


func test_set_not_installed() -> void:
	var r := GmParse.parse_ok(fx.run(GmCommands.set_default("9.9"))["stdout"])
	assert_false(r.ok)
	assert_eq(r.error.code, "not_installed")


func test_prune_dry_run_skips_custom_builds() -> void:
	var out := fx.run(GmCommands.prune(PackedStringArray([fx.root]), true))
	var r := GmParse.parse_prune(out["stdout"])
	if not assert_true(r.ok, str(r.error)):
		return
	assert_eq((r.value as PruneReport).candidates.size(), 0, "los builds propios no se tocan")
	assert_false((r.value as PruneReport).removed)


func test_path_status_parses() -> void:
	var r := GmParse.parse_path(fx.run(GmCommands.path_status())["stdout"])
	if not assert_true(r.ok, str(r.error)):
		return
	assert_eq((r.value as PathStatus).dir.replace("\\", "/"), fx.gm_bin.replace("\\", "/").get_base_dir())
