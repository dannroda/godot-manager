extends TestCase
## Actualizador en la UI (m5-16): parseo de `self-update --check`, ajustes,
## la franja (cuándo pregunta, qué muestra) y el final de Actualizar.

const BANNER := preload("res://panels/update_banner.tscn")
const CFG := "user://test_update_settings.cfg"

var banner: PanelContainer
var _old_available := false


func before_each() -> void:
	banner = BANNER.instantiate()
	tree.root.add_child(banner)
	_old_available = GmCli.available


func after_each() -> void:
	GmCli.available = _old_available
	banner.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	await wait_frames(1)


func _info(available := true, can := true) -> UpdateInfo:
	var u := UpdateInfo.new()
	u.current = "2.3.0"
	u.latest = "2.4.0"
	u.update_available = available
	u.can_update = can
	u.reason = "" if can else "lo instaló el gestor de paquetes en /usr/bin: actualizalo por ahí"
	u.url = "https://github.com/dannroda/godot-manager/releases/tag/v2.4.0"
	return u


func test_parse_update_check() -> void:
	var r := GmParse.parse_update_check("""{"current": "2.3.0", "latest": "2.4.0", "update_available": true,
		"can_update": false, "reason": "x", "url": "u", "asset": "a", "dir": "/d"}""")
	if not assert_true(r.ok, str(r.error)):
		return
	var u: UpdateInfo = r.value
	assert_eq(u.latest, "2.4.0")
	assert_true(u.update_available)
	assert_false(u.can_update)
	assert_eq(u.reason, "x")
	assert_eq(GmParse.parse_update_check("""{"latest": "2"}""").error.code, CliError.BAD_OUTPUT)
	assert_eq(GmParse.parse_update_check("""{"error": {"code": "unknown_command", "message": "m"}}""").error.code, "unknown_command")


func test_commands() -> void:
	assert_eq(GmCommands.self_update_check(), PackedStringArray(["--json", "self-update", "--check"]))
	assert_eq(GmCommands.self_update(), PackedStringArray(["--json", "self-update", "--yes"]))


func test_settings_persist() -> void:
	var s := AppSettings.new()
	assert_true(s.check_updates, "de fábrica busca")
	s.check_updates = false
	s.last_update_check = 1234
	s.save(CFG)
	var l := AppSettings.load_from(CFG)
	assert_false(l.check_updates)
	assert_eq(l.last_update_check, 1234)
	assert_eq(l.duplicate_settings().last_update_check, 1234)


func _button(name: String) -> Button:
	return banner.get_node("%" + name)


func test_show_info() -> void:
	banner.show_info(_info())
	assert_true(banner.visible)
	assert_eq((banner.get_node("%UpdateText") as Label).text, "Hay una versión nueva de godot-manager: 2.4.0 (tenés 2.3.0).")
	assert_true(_button("UpdateNow").visible)
	assert_true(_button("UpdateNotes").visible)

	banner.show_info(_info(true, false))
	assert_false(_button("UpdateNow").visible, "sin poder actualizar, solo novedades")
	assert_true((banner.get_node("%UpdateText") as Label).text.contains("gestor de paquetes"))

	banner.show_info(_info(false))
	assert_false(banner.visible, "al día: no se muestra")


func test_update_requested_and_finished() -> void:
	var got: Array = []
	banner.update_requested.connect(func(args: PackedStringArray, title: String) -> void: got.append([args, title]))
	banner.show_info(_info())
	_button("UpdateNow").pressed.emit()
	assert_eq(got.size(), 1)
	assert_eq(got[0][0], GmCommands.self_update())
	assert_eq(got[0][1], "Actualizar godot-manager a 2.4.0")

	var job := CliJob.new(GmCommands.self_update(), CliJob.Kind.WRITE)
	job.exit_code = 0
	job.state = CliJob.State.DONE
	banner.on_update_finished(job)
	assert_true(banner.updated)
	assert_false(_button("UpdateNow").visible)
	assert_true((banner.get_node("%UpdateText") as Label).text.begins_with("godot-manager se actualizó a 2.4.0."))
	assert_false(_button("UpdateRestart").visible, "en el editor no reinicia: no es la UI exportada")


func test_check_if_due() -> void:
	GmCli.available = false
	var s := AppSettings.new()
	var now := 1_000_000
	assert_false(banner.check_if_due(s, now), "sin CLI no pregunta")
	GmCli.available = true
	s.check_updates = false
	assert_false(banner.check_if_due(s, now), "apagado en Ajustes")
	s.check_updates = true
	s.last_update_check = now - 3600
	assert_false(banner.check_if_due(s, now), "ya preguntó hace una hora")
	assert_eq(s.last_update_check, now - 3600)
