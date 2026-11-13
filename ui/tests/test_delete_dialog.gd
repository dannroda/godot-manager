extends TestCase
## Diálogo de Borrar: lo que muestra y el `remove` que arma; y, contra el CLI
## real en un GODOT_DIR temporal, que ese comando borra lo que dice.

const DIALOG := preload("res://dialogs/delete_version_dialog.tscn")

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


func _version(name: String, is_default := false) -> InstalledVersion:
	var v := InstalledVersion.new()
	v.name = name
	v.path = "/opt/godot/versions/%s/godot" % name
	v.is_default = is_default
	return v


func test_shows_name_folder_and_no_warning() -> void:
	dialog.fill(_version("4.3-stable"))
	assert_eq((dialog.get_node("%VersionName") as Label).text, "4.3-stable")
	assert_eq((dialog.get_node("%Folder") as Label).text, "/opt/godot/versions/4.3-stable")
	assert_false((dialog.get_node("%DefaultWarning") as Label).visible)
	assert_eq(dialog.command(), GmCommands.remove("4.3-stable"))


func test_default_warning_and_templates() -> void:
	dialog.fill(_version("4.4-stable", true))
	assert_true((dialog.get_node("%DefaultWarning") as Label).visible)
	(dialog.get_node("%RemoveTemplates") as CheckBox).button_pressed = true
	assert_eq(dialog.command(), GmCommands.remove("4.4-stable", true))


func test_default_warning_does_not_stretch_dialog() -> void:
	dialog.open_for(_version("4.4-stable", true))
	await wait_frames(2)
	assert_true(dialog.size.y < 400, "alto razonable con el aviso (fue 1771 con el texto sin ancho mínimo): %s" % dialog.size)
	dialog.hide()


func test_fill_unticks_templates() -> void:
	dialog.fill(_version("a"))
	(dialog.get_node("%RemoveTemplates") as CheckBox).button_pressed = true
	dialog.fill(_version("b"))
	assert_eq(dialog.command(), GmCommands.remove("b"))


func test_confirm_emits_command() -> void:
	var got: Array = []
	dialog.delete_requested.connect(func(args: PackedStringArray) -> void: got.append(args))
	dialog.fill(_version("4.3-stable"))
	dialog.confirmed.emit()
	assert_eq(got, [GmCommands.remove("4.3-stable")])


func test_cancel_emits_nothing() -> void:
	var got: Array = []
	dialog.delete_requested.connect(func(args: PackedStringArray) -> void: got.append(args))
	dialog.fill(_version("4.3-stable"))
	dialog.canceled.emit()
	assert_eq(got, [])


func _needs_fixture() -> bool:
	fx = CliFixture.new()
	if not fx.available():
		skip(fx.why_unavailable())
		return false
	if not fx.setup(["4.2-fake", "4.3-fake"]):
		fail(fx.last_error)
		return false
	return true


func _list() -> Dictionary:
	var r := GmParse.parse_list(fx.run(GmCommands.list())["stdout"])
	var names: Array = []
	var default_name := ""
	for v: InstalledVersion in r.value:
		names.append(v.name)
		if v.is_default:
			default_name = v.name
	return {"names": names, "default": default_name}


func test_cli_remove_with_and_without_templates() -> void:
	if not _needs_fixture():
		return
	var versions := _list()
	dialog.fill(_version("4.2-fake"))
	var r := GmParse.parse_ok(fx.run(dialog.command())["stdout"])
	if not assert_true(r.ok, str(r.error)):
		return
	assert_eq(_list()["names"], ["4.3-fake"])
	dialog.fill(_version("4.3-fake"))
	(dialog.get_node("%RemoveTemplates") as CheckBox).button_pressed = true
	r = GmParse.parse_ok(fx.run(dialog.command())["stdout"])
	if not assert_true(r.ok, str(r.error)):
		return
	assert_eq(r.value["version"], "4.3-fake")
	assert_eq(_list()["names"], [], "antes: %s" % [versions["names"]])


func test_cli_remove_default_leaves_no_default() -> void:
	if not _needs_fixture():
		return
	fx.run(GmCommands.set_default("4.3-fake"))
	assert_eq(_list()["default"], "4.3-fake")
	dialog.fill(_version("4.3-fake", true))
	var r := GmParse.parse_ok(fx.run(dialog.command())["stdout"])
	if not assert_true(r.ok, str(r.error)):
		return
	var after := _list()
	assert_eq(after["names"], ["4.2-fake"])
	assert_eq(after["default"], "")
