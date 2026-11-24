extends TestCase
## Pestaña Descargar: acciones según lo instalado, Desinstalar… (columna, menú
## contextual y atajo Supr), edición faltante preseleccionada y selector cuando
## coinciden normal y mono.

const SCREEN := preload("res://screens/remote_screen.tscn")

var screen: Control


func before_each() -> void:
	screen = SCREEN.instantiate()
	screen.visible = false
	tree.root.add_child(screen)


func after_each() -> void:
	screen.queue_free()
	await wait_frames(1)


func _release(tag: String, editor := true, mono := true) -> RemoteVersion:
	var r := RemoteVersion.new()
	r.tag = tag
	r.editor = editor
	r.mono = mono
	r.templates = true
	r.mono_templates = mono
	return r


func _installed(name: String, tag: String, mono := false) -> InstalledVersion:
	var v := InstalledVersion.new()
	v.name = name
	v.tag = tag
	v.mono = mono
	v.path = "/opt/godot/versions/%s/godot" % name
	return v


func _populate(rels: Array[RemoteVersion], inst: Array[InstalledVersion]) -> void:
	screen.releases.assign(rels)
	screen.installed.assign(inst)
	screen._marks = RemoteFilter.installed_marks(screen.installed)
	screen._rebuild()
	screen._update_actions()


func _row_for(tag: String) -> Control:
	for row in screen.get_node("%Rows").get_children():
		if row.release.tag == tag:
			return row
	return null


func _menu_texts(menu: PopupMenu) -> PackedStringArray:
	var out := PackedStringArray()
	for i in menu.item_count:
		out.append("---" if menu.is_item_separator(i) else menu.get_item_text(i))
	return out


func test_actions_follow_installed_state() -> void:
	var r_new := _release("4.7.2-stable")
	var r_partial := _release("4.7.1-stable", true, true)
	var r_only_std := _release("4.7.0-stable", true, false)
	var r_no_ed := _release("3.6-stable", false, false)
	_populate(
		[r_new, r_partial, r_only_std, r_no_ed],
		[
			_installed("4.7.1-stable", "4.7.1-stable"),
			_installed("4.7.0-stable", "4.7.0-stable"),
		])

	var install: Button = screen.get_node("%Install")
	var uninstall: Button = screen.get_node("%Uninstall")
	var notes: Button = screen.get_node("%ReleaseNotes")

	# Sin selección.
	assert_true(install.disabled)
	assert_eq(install.text, "Instalar…")
	assert_false(uninstall.visible)
	assert_true(notes.disabled)

	# Release no instalada.
	screen._on_row_selected(_row_for("4.7.2-stable"))
	assert_false(install.disabled)
	assert_eq(install.text, "Instalar…")
	assert_eq(install.tooltip_text, "")
	assert_false(uninstall.visible)
	assert_false(notes.disabled)

	# Release sin editor en esta plataforma.
	screen._on_row_selected(_row_for("3.6-stable"))
	assert_true(install.disabled)
	assert_eq(install.text, "Instalar…")
	assert_false(install.tooltip_text.is_empty())
	assert_false(uninstall.visible)

	# Solo normal instalada en release con mono: Instalar… sigue habilitado y aparece Desinstalar….
	screen._on_row_selected(_row_for("4.7.1-stable"))
	assert_false(install.disabled)
	assert_eq(install.text, "Instalar…")
	assert_eq(install.tooltip_text, "")
	assert_true(uninstall.visible)
	assert_false(uninstall.disabled)
	assert_eq(uninstall.text, "Desinstalar…")

	# Release sin mono con la normal instalada: todas las ediciones instaladas → Instalar… deshabilitado con tooltip.
	screen._on_row_selected(_row_for("4.7.0-stable"))
	assert_true(install.disabled)
	assert_eq(install.text, "Instalar…")
	assert_eq(install.tooltip_text, "Esta versión ya está instalada.")
	assert_true(uninstall.visible)
	assert_false(uninstall.disabled)


func test_partial_edition_installs_missing_edition() -> void:
	var r_std := _release("4.7.1-stable", true, true)
	var r_mono := _release("4.7.0-stable", true, true)
	_populate(
		[r_std, r_mono],
		[
			_installed("4.7.1-stable", "4.7.1-stable", false),
			_installed("4.7.0-stable-mono", "4.7.0-stable", true),
		])

	var install: Button = screen.get_node("%Install")
	var uninstall: Button = screen.get_node("%Uninstall")
	var install_dlg: ConfirmationDialog = screen.get_node("%InstallDialog")

	# Solo normal instalada → Instalar… abre en modo INSTALL con mono marcada, Desinstalar… visible.
	screen._on_row_selected(_row_for("4.7.1-stable"))
	assert_false(install.disabled)
	assert_eq(install.text, "Instalar…")
	assert_true(uninstall.visible)
	install.pressed.emit()
	assert_true(install_dlg.visible)
	assert_eq(install_dlg.options.mode, InstallOptions.Mode.INSTALL)
	assert_eq(install_dlg.options.version, "4.7.1-stable")
	assert_true(install_dlg.options.mono, "marca mono porque ya está instalada la normal")
	install_dlg.hide()

	# Solo mono instalada → Instalar… abre en modo INSTALL con normal marcada.
	screen._on_row_selected(_row_for("4.7.0-stable"))
	assert_false(install.disabled)
	assert_eq(install.text, "Instalar…")
	assert_true(uninstall.visible)
	install.pressed.emit()
	assert_true(install_dlg.visible)
	assert_eq(install_dlg.options.mode, InstallOptions.Mode.INSTALL)
	assert_false(install_dlg.options.mono, "marca normal porque ya está instalada la mono")
	install_dlg.hide()

	# Con las dos instaladas → Instalar… queda deshabilitado con tooltip.
	_populate(
		[r_std],
		[
			_installed("4.7.1-stable", "4.7.1-stable", false),
			_installed("4.7.1-stable-mono", "4.7.1-stable", true),
		])
	screen._on_row_selected(_row_for("4.7.1-stable"))
	assert_true(install.disabled)
	assert_eq(install.text, "Instalar…")
	assert_eq(install.tooltip_text, "Esta versión ya está instalada.")
	assert_true(uninstall.visible)


func test_context_menu_includes_uninstall_only_when_installed() -> void:
	_populate(
		[_release("4.7.2-stable"), _release("4.7.1-stable", true, false)],
		[_installed("4.7.1-stable", "4.7.1-stable")])

	var menu: PopupMenu = screen._on_row_context(_row_for("4.7.2-stable"), Vector2(10, 10))
	assert_eq(_menu_texts(menu), PackedStringArray(["Instalar…", "Ver en GitHub"]))
	assert_false(menu.is_item_disabled(0))
	menu.hide()

	menu = screen._on_row_context(_row_for("4.7.1-stable"), Vector2(10, 10))
	assert_eq(_menu_texts(menu), PackedStringArray(["Instalar…", "Ver en GitHub", "---", "Desinstalar…"]))
	assert_true(menu.is_item_disabled(0))
	assert_false(menu.is_item_disabled(3))
	menu.hide()


func test_single_installed_opens_dialogs_directly() -> void:
	_populate(
		[_release("4.7.2-stable"), _release("4.7.1-stable", true, false)],
		[_installed("4.7.1-stable", "4.7.1-stable")])

	var install_dlg: ConfirmationDialog = screen.get_node("%InstallDialog")
	var delete_dlg: ConfirmationDialog = screen.get_node("%DeleteDialog")

	# No instalada → InstallDialog en modo INSTALL.
	screen._on_row_selected(_row_for("4.7.2-stable"))
	(screen.get_node("%Install") as Button).pressed.emit()
	assert_true(install_dlg.visible)
	assert_eq(install_dlg.options.mode, InstallOptions.Mode.INSTALL)
	assert_eq(install_dlg.options.version, "4.7.2-stable")
	assert_false(install_dlg.options.mono)
	install_dlg.hide()

	# Instalada (una sola edición) → borrar abre directo sin menú intermedio.
	screen._on_row_selected(_row_for("4.7.1-stable"))
	(screen.get_node("%Uninstall") as Button).pressed.emit()
	assert_true(delete_dlg.visible)
	assert_eq(delete_dlg.version.name, "4.7.1-stable")
	assert_true(screen.get_node_or_null("EditionPickerMenu") == null)
	delete_dlg.hide()


func test_multiple_editions_shows_picker_for_uninstall() -> void:
	_populate(
		[_release("4.7.1-stable")],
		[
			_installed("4.7.1-stable-mono", "4.7.1-stable", true),
			_installed("4.7.1-stable", "4.7.1-stable", false),
		])
	screen._on_row_selected(_row_for("4.7.1-stable"))

	var delete_dlg: ConfirmationDialog = screen.get_node("%DeleteDialog")
	(screen.get_node("%Uninstall") as Button).pressed.emit()
	var picker := screen.get_node_or_null("EditionPickerMenu") as PopupMenu
	if not assert_true(picker != null and picker.visible, "muestra selector cuando hay normal y mono"):
		return
	assert_eq(_menu_texts(picker), PackedStringArray(["4.7.1-stable", "4.7.1-stable-mono"]))
	picker.id_pressed.emit(1)
	picker.hide()
	assert_true(delete_dlg.visible)
	assert_eq(delete_dlg.version.name, "4.7.1-stable-mono")
	delete_dlg.hide()


func test_buttons_refresh_when_installed_changes_and_delete_shortcut() -> void:
	_populate(
		[_release("4.7.1-stable", true, false)],
		[_installed("4.7.1-stable", "4.7.1-stable")])
	screen._on_row_selected(_row_for("4.7.1-stable"))
	assert_true((screen.get_node("%Install") as Button).disabled)

	assert_true(screen.handle_shortcut(&"gm_delete"), "Supr abre el diálogo cuando está instalada")
	var delete_dlg: ConfirmationDialog = screen.get_node("%DeleteDialog")
	assert_true(delete_dlg.visible)
	delete_dlg.hide()

	# Al desinstalar, refresh_installed vuelve a llenar `installed` y `_marks` sin cambiar la selección.
	_populate([_release("4.7.1-stable", true, false)], [])
	assert_eq(screen.selected.tag, "4.7.1-stable", "se mantiene la selección")
	assert_false((screen.get_node("%Uninstall") as Button).visible)
	assert_false((screen.get_node("%Install") as Button).disabled)
	assert_eq((screen.get_node("%Install") as Button).text, "Instalar…")
	assert_false(screen.handle_shortcut(&"gm_delete"), "Supr no hace nada si ya no está instalada")
