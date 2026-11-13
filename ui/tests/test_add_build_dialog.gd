extends TestCase
## Diálogo Agregar build propio: validación, comando, y contra el CLI real en
## un GODOT_DIR temporal, que agrega con y sin --symlink.

const DIALOG := preload("res://dialogs/add_build_dialog.tscn")

var dialog: ConfirmationDialog
var fx: CliFixture


func before_each() -> void:
	dialog = DIALOG.instantiate()
	tree.root.add_child(dialog)


func after_each() -> void:
	dialog.queue_free()
	if fx != null:
		fx.teardown()
		fx = null
	await wait_frames(1)


func _type(name: String, path: String) -> void:
	var n: LineEdit = dialog.get_node("%BuildName")
	var p: LineEdit = dialog.get_node("%BuildPath")
	n.text = name
	n.text_changed.emit(name)
	p.text = path
	p.text_changed.emit(path)


func _ok_disabled() -> bool:
	return dialog.get_ok_button().disabled


func test_starts_disabled_and_validates() -> void:
	dialog.reset(PackedStringArray(["4.3-stable"]))
	assert_true(_ok_disabled(), "vacío")
	_type("mio", "")
	assert_true(_ok_disabled(), "sin ruta")
	_type("4.3-stable", "/bin/true")
	assert_true(_ok_disabled(), "nombre repetido")
	assert_eq((dialog.get_node("%Hint") as Label).text, "Ya hay una versión llamada «4.3-stable».")
	_type("  mio ", " /bin/true ")
	assert_false(_ok_disabled())
	assert_eq((dialog.get_node("%Hint") as Label).text, "")
	assert_eq(dialog.command(), GmCommands.add("mio", "/bin/true"))


## 2.2: con un nombre repetido se ofrece reemplazar (--force).
func test_replace_existing() -> void:
	dialog.reset(PackedStringArray(["mio"]))
	var replace: CheckBox = dialog.get_node("%Replace")
	_type("otro", "/bin/true")
	assert_false(replace.visible, "nombre libre: sin la opción")
	_type("mio", "/bin/true")
	assert_true(replace.visible)
	assert_true(_ok_disabled(), "sin marcarla no se puede")
	replace.button_pressed = true
	assert_false(_ok_disabled())
	assert_eq(dialog.ok_button_text, "Reemplazar")
	assert_has((dialog.get_node("%Hint") as Label).text, "Se borra la versión «mio»")
	assert_eq(dialog.command(), GmCommands.add("mio", "/bin/true", false, true))
	_type("otro", "/bin/true")
	assert_eq(dialog.command(), GmCommands.add("otro", "/bin/true"), "sin repetir, sin --force aunque esté marcada")
	assert_eq(dialog.ok_button_text, "Agregar")
	dialog.reset(PackedStringArray(["mio"]))
	assert_false(replace.button_pressed)


func test_symlink_and_reset() -> void:
	dialog.reset(PackedStringArray())
	_type("mio", "/bin/true")
	(dialog.get_node("%Symlink") as CheckBox).button_pressed = true
	assert_eq(dialog.command(), GmCommands.add("mio", "/bin/true", true))
	dialog.reset(PackedStringArray())
	assert_eq((dialog.get_node("%BuildName") as LineEdit).text, "")
	assert_false((dialog.get_node("%Symlink") as CheckBox).button_pressed)
	assert_true(_ok_disabled())


func test_confirm_and_enter_emit_command() -> void:
	var got: Array = []
	dialog.add_requested.connect(func(args: PackedStringArray) -> void: got.append(args))
	dialog.reset(PackedStringArray())
	_type("mio", "/bin/true")
	dialog.confirmed.emit()
	(dialog.get_node("%BuildPath") as LineEdit).text_submitted.emit("/bin/true")
	assert_eq(got, [GmCommands.add("mio", "/bin/true"), GmCommands.add("mio", "/bin/true")])


func test_enter_with_problem_does_nothing() -> void:
	var got: Array = []
	dialog.add_requested.connect(func(args: PackedStringArray) -> void: got.append(args))
	dialog.reset(PackedStringArray())
	_type("mio", "")
	(dialog.get_node("%BuildName") as LineEdit).text_submitted.emit("mio")
	assert_eq(got, [])


func _needs_fixture() -> bool:
	fx = CliFixture.new()
	if not fx.available():
		skip(fx.why_unavailable())
		return false
	if not fx.setup([]):
		fail(fx.last_error)
		return false
	return true


func test_cli_add_copy_and_symlink() -> void:
	if not _needs_fixture():
		return
	var exe := CliFixture.fake_executable()
	dialog.reset(PackedStringArray())
	_type("copiado", exe)
	var r := GmParse.parse_ok(fx.run(dialog.command())["stdout"])
	if not assert_true(r.ok, str(r.error)):
		return
	_type("enlazado", exe)
	(dialog.get_node("%Symlink") as CheckBox).button_pressed = true
	r = GmParse.parse_ok(fx.run(dialog.command())["stdout"])
	if not assert_true(r.ok, str(r.error)):
		return
	var l := GmParse.parse_list(fx.run(GmCommands.list())["stdout"])
	var by_name := {}
	for v: InstalledVersion in l.value:
		by_name[v.name] = v
	assert_eq(by_name.keys(), ["copiado", "enlazado"])
	for n: String in by_name:
		assert_true((by_name[n] as InstalledVersion).custom, n)
	var copied: String = (by_name["copiado"] as InstalledVersion).path
	var linked: String = (by_name["enlazado"] as InstalledVersion).path
	if OS.get_name() != "Windows":
		assert_eq(DirAccess.open(copied.get_base_dir()).is_link(copied), false, "copia")
		assert_eq(DirAccess.open(linked.get_base_dir()).is_link(linked), true, "enlace")


## 2.2: `add` con un nombre que ya existe da already_installed; con
## "Reemplazar la existente" (--force) lo reemplaza.
func test_cli_add_existing_and_force() -> void:
	if not _needs_fixture():
		return
	var ver := GmParse.version_numbers(str(fx.run(GmCommands.cli_version())["stdout"]).strip_edges())
	if ver.size() < 2 or ver[0] < 2 or (ver[0] == 2 and ver[1] < 2):
		skip("necesita godot-manager 2.2 o posterior")
		return
	var exe := CliFixture.fake_executable()
	assert_true(GmParse.parse_ok(fx.run(GmCommands.add("mio", exe))["stdout"]).ok)
	dialog.reset(PackedStringArray(["mio"]))
	_type("mio", exe)
	var repeated := GmParse.parse_ok(fx.run(GmCommands.add("mio", exe))["stdout"])
	assert_false(repeated.ok)
	if repeated.error != null:
		assert_eq(repeated.error.code, "already_installed")
	(dialog.get_node("%Replace") as CheckBox).button_pressed = true
	var forced := GmParse.parse_ok(fx.run(dialog.command())["stdout"])
	assert_true(forced.ok, str(forced.error))
	var l := GmParse.parse_list(fx.run(GmCommands.list())["stdout"])
	assert_eq((l.value as Array).size(), 1, "sigue habiendo una sola")


func test_cli_rejects_bad_name() -> void:
	if not _needs_fixture():
		return
	dialog.reset(PackedStringArray())
	_type("a/b", CliFixture.fake_executable())
	assert_false(_ok_disabled(), "el nombre lo valida el CLI")
	var out := fx.run(dialog.command())
	assert_eq(out["exit"], 1)
	var r := GmParse.parse_ok(out["stdout"])
	assert_false(r.ok)
	assert_eq(r.error.code, "invalid_args")
