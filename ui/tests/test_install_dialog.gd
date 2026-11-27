extends TestCase
## Diálogo de instalación: lo que se tilda llega a la vista previa, y lo que
## la release no trae queda deshabilitado.

const DIALOG := preload("res://dialogs/install_dialog.tscn")

var dialog: ConfirmationDialog


func before_each() -> void:
	dialog = DIALOG.instantiate()
	tree.root.add_child(dialog)


func after_each() -> void:
	dialog.queue_free()
	await wait_frames(1)


func _release(tag: String) -> RemoteVersion:
	var r := GmParse.parse_remote(FileAccess.get_file_as_string("res://tests/fixtures/list_remote.json"))
	for rel: RemoteVersion in r.value:
		if rel.tag == tag:
			return rel
	return null


func _box(name: String) -> CheckBox:
	return dialog.form.get_node("%" + name)


func _platform(p: String) -> CheckBox:
	for box: CheckBox in dialog.form.get_node("%PlatformGrid").get_children():
		if box.text == p:
			return box
	return null


func _preview() -> String:
	return (dialog.form.get_node("%Command") as Label).text


func test_task_example_preview() -> void:
	dialog.fill(_release("4.8-beta3"))
	assert_eq(_preview(), "godot-manager --json install 4.8-beta3")
	_box("Mono").button_pressed = true
	_box("Symbols").button_pressed = true
	_box("Templates").button_pressed = true
	assert_true((dialog.form.get_node("%PlatformGrid") as Control).visible)
	assert_eq(_preview(), "godot-manager --json install 4.8-beta3 --mono --debugsymbols --templates",
		"al activar templates arrancan todas")
	for p in GmCommands.PLATFORMS:
		if p != "linux" and p != "windows":
			_platform(p).button_pressed = false
	assert_eq(_preview(), "godot-manager --json install 4.8-beta3 --mono --debugsymbols --platforms=linux,windows")
	assert_eq(dialog.options.command(), PackedStringArray(["--json", "install", "4.8-beta3", "--mono",
		"--debugsymbols", "--platforms=linux,windows"]), "lo que se corre es lo que se ve")


func test_no_platform_disables_ok() -> void:
	dialog.fill(_release("4.8-beta3"))
	_box("Templates").button_pressed = true
	for p in GmCommands.PLATFORMS:
		_platform(p).button_pressed = false
	assert_true(dialog.get_ok_button().disabled)
	assert_true((dialog.form.get_node("%Hint") as Label).visible)
	_platform("web").button_pressed = true
	assert_false(dialog.get_ok_button().disabled)


func test_release_without_symbols() -> void:
	dialog.fill(_release("4.7.2-stable"))
	assert_true(_box("Symbols").disabled, "4.7.2 no trae símbolos")
	assert_false(_box("Mono").disabled)
	assert_false(_box("Templates").disabled)


func test_fill_resets_and_size() -> void:
	dialog.fill(_release("4.8-beta3"))
	_box("Mono").button_pressed = true
	_box("Templates").button_pressed = true
	assert_true((dialog.form.get_node("%Size") as Label).text.begins_with("Descarga: "))
	dialog.fill(_release("4.8-beta2"))
	assert_false(_box("Mono").button_pressed)
	assert_false(_box("Templates").button_pressed)
	assert_eq(_preview(), "godot-manager --json install 4.8-beta2")


func test_unknown_fields_leave_everything_enabled() -> void:
	var r: RemoteVersion = GmParse.parse_remote('[{"tag":"4.3-stable"}]').value[0]
	dialog.fill(r)
	for box in ["Mono", "Symbols", "Templates"]:
		assert_false(_box(box).disabled, box)
	assert_false((dialog.form.get_node("%Size") as Label).visible, "sin tamaños no se muestra")


func test_mono_without_mono_templates() -> void:
	var r: RemoteVersion = GmParse.parse_remote('[{"tag":"4.9-stable","mono_templates":false}]').value[0]
	dialog.fill(r)
	_box("Templates").button_pressed = true
	_box("Mono").button_pressed = true
	assert_true(_box("Templates").disabled, "sin templates mono, con Mono se apagan")
	assert_false(_box("Templates").button_pressed)
	_box("Normal").button_pressed = true
	assert_false(_box("Templates").disabled)


func test_templates_mode() -> void:
	var v := InstalledVersion.new()
	v.name = "4.7.2-stable-mono"
	v.tag = "4.7.2-stable"
	v.mono = true
	v.template_platforms = PackedStringArray(["linux"])
	var got: Array = []
	dialog.install_requested.connect(func(args: PackedStringArray, t: String) -> void: got.append([args, t]))
	dialog.fill_templates(v)
	assert_false((dialog.form.get_node("%EditionRow") as Control).visible, "la edición sale de la versión")
	assert_false(_box("Templates").visible)
	assert_true((dialog.form.get_node("%PlatformGrid") as Control).visible)
	assert_eq(_platform("linux (instalado)").button_pressed, false, "la que ya tiene, marcada y sin tildar")
	for p in GmCommands.PLATFORMS:
		if p != "linux":
			_platform(p).button_pressed = p == "windows"
	_box("Symbols").button_pressed = true
	assert_eq(_preview(), "godot-manager --json templates 4.7.2-stable --mono --platforms=windows --debugsymbols")
	dialog.confirmed.emit()
	assert_eq(got[0][1], "Instalando templates de 4.7.2-stable (mono)")
	dialog.fill(_release("4.8-beta3"))
	assert_true((dialog.form.get_node("%EditionRow") as Control).visible, "volver a modo instalar")
	assert_eq(_platform("linux").text, "linux")


func test_confirm_emits_command_and_title() -> void:
	var got: Array = []
	dialog.install_requested.connect(func(args: PackedStringArray, t: String) -> void: got.append([args, t]))
	dialog.fill(_release("4.8-beta3"))
	_box("Mono").button_pressed = true
	dialog.confirmed.emit()
	assert_eq(got, [[PackedStringArray(["--json", "install", "4.8-beta3", "--mono"]), "Instalando 4.8-beta3 (mono)"]])
