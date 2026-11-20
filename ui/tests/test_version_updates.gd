extends TestCase
## Versiones: la etiqueta y el botón Actualizar cuando `outdated` dice que hay
## una más nueva de la serie, y Ajustes con el estado del PATH.

const INSTALLED := preload("res://screens/installed_screen.tscn")
const SETTINGS := preload("res://dialogs/settings_dialog.tscn")

var screen: Control
var settings: ConfirmationDialog


func after_each() -> void:
	for n: Node in [screen, settings]:
		if n != null:
			n.queue_free()
	screen = null
	settings = null
	await wait_frames(1)


func _version(name: String) -> InstalledVersion:
	var v := InstalledVersion.new()
	v.name = name
	v.path = "/v/%s/godot" % name
	v.tag = name
	return v


func _update(version: String, latest: String, installed := false) -> VersionUpdate:
	var u := VersionUpdate.new()
	u.version = version
	u.latest = latest
	u.installed = installed
	return u


func _screen_with_updates() -> void:
	screen = INSTALLED.instantiate()
	tree.root.add_child(screen)
	screen.versions.assign([_version("4.5-stable"), _version("4.8-beta2"), _version("4.7-stable")])
	screen._updates = {"4.5-stable": _update("4.5-stable", "4.5.2-stable"),
		"4.8-beta2": _update("4.8-beta2", "4.8-beta4", true)}
	screen._rebuild()


func _row(name: String) -> Control:
	for r in screen.get_node("%Rows").get_children():
		if r.version.name == name:
			return r
	return null


func _tag_texts(row: Control) -> PackedStringArray:
	var out := PackedStringArray()
	for t in row.get_node("%Tags").get_children():
		if not t.is_queued_for_deletion():
			out.append((t.get_node("Text") as Label).text)
	return out


func test_rows_show_newer_version() -> void:
	_screen_with_updates()
	await wait_frames(1)
	assert_has(_tag_texts(_row("4.5-stable")), "Nueva: 4.5.2-stable")
	assert_eq(_tag_texts(_row("4.7-stable")), PackedStringArray())


func test_upgrade_button_follows_selection() -> void:
	_screen_with_updates()
	await wait_frames(1)
	var upgrade: Button = screen.get_node("%Upgrade")
	screen._on_row_selected(_row("4.7-stable"))
	assert_false(upgrade.visible, "sin versión nueva no aparece")
	screen._on_row_selected(_row("4.8-beta2"))
	assert_true(upgrade.visible)
	assert_true(upgrade.disabled, "la nueva ya está instalada")
	screen._on_row_selected(_row("4.5-stable"))
	assert_false(upgrade.disabled)
	assert_has(upgrade.tooltip_text, "4.5.2-stable")
	var asked: Array = []
	screen.install_requested.connect(func(args: PackedStringArray, title: String) -> void:
		asked.append([args, title]))
	upgrade.pressed.emit()
	assert_eq(asked, [[GmCommands.upgrade("4.5-stable"), "Actualizando 4.5-stable a 4.5.2-stable"]])


func test_settings_path_status() -> void:
	settings = SETTINGS.instantiate()
	tree.root.add_child(settings)
	var label: Label = settings.get_node("%PathStatus")
	var button: Button = settings.get_node("%PathButton")
	var st := PathStatus.new()
	st.target = "~/.local/bin"
	settings.show_path_status(st)
	assert_true(button.visible)
	assert_eq(button.text, "Agregar al PATH")
	assert_has(label.text, "~/.local/bin")
	st.on_path = true
	settings.show_path_status(st)
	assert_eq(button.text, "Quitar del PATH")
	st.managed = "Scoop"
	settings.show_path_status(st)
	assert_false(button.visible, "lo maneja el gestor de paquetes")
	assert_has(label.text, "Scoop")


func test_settings_default_dir() -> void:
	settings = SETTINGS.instantiate()
	tree.root.add_child(settings)
	var field: LineEdit = settings.get_node("%GodotDir")
	var reset: Button = settings.get_node("%ResetDir")
	var help: Label = settings.get_node("%DirHelp")
	# Guardada vacía: muestra la por defecto y no hay nada que restaurar.
	settings.set_default_dir("C:/Users/x/AppData/Local/godot-manager")
	assert_eq(field.text, "C:/Users/x/AppData/Local/godot-manager")
	assert_true(reset.disabled)
	assert_eq(settings.current_settings().godot_dir, "", "la por defecto se guarda vacía")
	assert_has(help.text, "por defecto")
	# Una propia: se guarda tal cual y Restaurar vuelve a la por defecto.
	field.text = "D:/godot"
	field.text_changed.emit(field.text)
	assert_false(reset.disabled)
	assert_eq(settings.current_settings().godot_dir, "D:/godot")
	assert_has(help.text, "C:/Users/x/AppData/Local/godot-manager")
	reset.pressed.emit()
	assert_eq(field.text, "C:/Users/x/AppData/Local/godot-manager")
	assert_true(reset.disabled)
	# La misma con otra barra final (y en Windows otras mayúsculas) sigue siendo la por defecto.
	assert_true(settings.is_default_dir("C:/Users/x/AppData/Local/godot-manager/"))
	assert_true(settings.is_default_dir(""))
