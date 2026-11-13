extends TestCase
## Pestaña Proyectos con una lista temporal: agregar, escanear, quitar,
## persistencia y filtro.

const SCREEN := preload("res://screens/projects_screen.tscn")
const CFG := "user://test_projects_screen.cfg"

var root := ""
var screen: Control


func before_each() -> void:
	root = ProjectSettings.globalize_path("user://test_projects_screen_tree")
	_remove_tree(root)
	DirAccess.make_dir_recursive_absolute(root)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	screen = _new_screen()


func after_each() -> void:
	screen.queue_free()
	await wait_frames(1)
	_remove_tree(root)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))


func _new_screen() -> Control:
	var s := SCREEN.instantiate()
	s.list_path = CFG
	tree.root.add_child(s)
	return s


func _remove_tree(dir: String) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.include_hidden = true
	for f in da.get_files():
		da.remove(f)
	for d in da.get_directories():
		_remove_tree(dir.path_join(d))
	DirAccess.remove_absolute(dir)


func _project(rel: String, project_name: String) -> String:
	var dir := root.path_join(rel)
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("project.godot"), FileAccess.WRITE)
	f.store_string("config_version=5\n[application]\nconfig/name=\"%s\"\nconfig/features=PackedStringArray(\"4.8\")\n" % project_name)
	f.close()
	return dir


func _names() -> PackedStringArray:
	var out := PackedStringArray()
	for e: ProjectEntry in screen.visible_projects():
		out.append(e.name)
	return out


func test_empty_shows_placeholder() -> void:
	var state: ListState = screen.get_node("%Placeholder")
	assert_true(state.visible)
	assert_eq(state.kind, ListState.Kind.INFO)
	assert_eq(state.action_labels(), PackedStringArray(["Agregar…", "Escanear…", "Importar de Godot"]),
		"vacía: con las tres formas de llenarla")
	screen.get_node("%Search").text = "x"
	screen.add_project(_project("a", "Alfa"))
	screen.get_node("%Search").text_changed.emit("zzz")
	assert_eq(state.text, "Ningún proyecto coincide con la búsqueda.")
	state.first_action().pressed.emit()
	assert_eq(screen.get_node("%Search").text, "", "Mostrar todos vacía la búsqueda")
	assert_false(state.visible)
	assert_true((screen.get_node("%Remove") as Button).disabled)


func test_add_select_and_persist() -> void:
	var a := _project("a", "Alfa")
	assert_true(screen.add_project(a))
	assert_eq(_names(), PackedStringArray(["Alfa"]))
	assert_eq(screen.selected.path, a, "lo recién agregado queda seleccionado")
	assert_false((screen.get_node("%Remove") as Button).disabled)
	assert_true(screen.add_project(a + "/"), "repetido: no falla, lo selecciona")
	assert_eq(screen.entries.size(), 1)
	assert_has((screen.get_node("%Status") as Label).text, "ya estaba")
	var other := _new_screen()
	assert_eq(other.list.paths, PackedStringArray([a]), "se guardó")
	other.queue_free()


func test_add_folder_without_project() -> void:
	DirAccess.make_dir_recursive_absolute(root.path_join("vacia"))
	assert_false(screen.add_project(root.path_join("vacia")))
	assert_eq(screen.entries.size(), 0)
	assert_true((screen.get_node("%MessageDialog") as AcceptDialog).visible)
	(screen.get_node("%MessageDialog") as AcceptDialog).hide()


func test_scan_adds_new_ones() -> void:
	var a := _project("a", "Alfa")
	_project("juegos/b", "Beta")
	_project("juegos/b/.godot/x", "Fantasma")
	screen.add_project(a)
	var added: int = await screen.scan_folder(root)
	assert_eq(added, 1)
	assert_false(screen.is_scanning())
	var names := _names()
	names.sort()
	assert_eq(names, PackedStringArray(["Alfa", "Beta"]), "sin el de .godot")
	assert_eq(screen.entries.size(), 2)
	assert_has((screen.get_node("%Status") as Label).text, "Se encontraron 2 proyectos")
	assert_eq(screen.list.last_scan_dir, root)


func test_remove_keeps_files() -> void:
	var a := _project("a", "Alfa")
	screen.add_project(a)
	screen.remove_project(a)
	assert_eq(screen.entries.size(), 0)
	assert_eq(screen.selected, null)
	assert_true(FileAccess.file_exists(a.path_join("project.godot")), "no borra nada")
	var other := _new_screen()
	assert_eq(other.list.paths.size(), 0)
	other.queue_free()


func test_search_and_sort() -> void:
	screen.add_project(_project("z", "Zeta"))
	screen.add_project(_project("m", "Mu"))
	var sort: OptionButton = screen.get_node("%Sort")
	sort.select(sort.get_item_index(ProjectList.Sort.NAME))
	sort.item_selected.emit(sort.selected)
	assert_eq(_names(), PackedStringArray(["Mu", "Zeta"]))
	(screen.get_node("%Search") as LineEdit).text = "zet"
	(screen.get_node("%Search") as LineEdit).text_changed.emit("zet")
	assert_eq(_names(), PackedStringArray(["Zeta"]))
	assert_eq(ProjectList.load_from(CFG).sort, ProjectList.Sort.NAME, "el orden se guarda")


## 3.5: importar del projects.cfg del Project Manager (de ejemplo).
func test_import_from_pm() -> void:
	var a := _project("a", "Alfa")
	var b := _project("b", "Beta")
	screen.add_project(a)
	var cfg := root.path_join("projects.cfg")
	var f := FileAccess.open(cfg, FileAccess.WRITE)
	f.store_string("[%s]\n\nfavorite=false\n\n[%s/]\n\nfavorite=true\n\n[%s]\n\nfavorite=false\n" % [
		a, b, root.path_join("borrado")])
	f.close()
	var before := FileAccess.get_file_as_string(cfg)
	assert_eq(screen.import_from_pm(cfg), 1)
	assert_eq(screen.list.paths, PackedStringArray([a, b]), "sin repetir; la barra final no importa")
	assert_eq((screen.get_node("%Status") as Label).text,
		"Del Project Manager: 1 nuevos, 1 ya estaban, 1 ya no existen (no se agregaron).")
	assert_eq(FileAccess.get_file_as_string(cfg), before, "solo lee")
	assert_eq(screen.import_from_pm(root.path_join("no_existe.cfg")), 0)
	assert_true((screen.get_node("%MessageDialog") as AcceptDialog).visible)
	(screen.get_node("%MessageDialog") as AcceptDialog).hide()


func test_pm_config_path_per_os() -> void:
	var p := ProjectList.pm_config_path()
	assert_true(p.ends_with("projects.cfg"))
	if OS.get_name() == "Linux":
		assert_true(p.ends_with("godot/projects.cfg"))


## 4.1: atajos que main le pasa a la pestaña, y foco con teclado.
func test_keyboard_shortcuts() -> void:
	screen.add_project(_project("a", "Alfa"))
	screen.add_project(_project("b", "Beta"))
	var vp := screen.get_viewport()
	var search: LineEdit = screen.get_node("%Search")
	search.text = "be"
	assert_true(screen.handle_shortcut(&"gm_search"))
	assert_eq(vp.gui_get_focus_owner(), search, "Ctrl+F: foco a la búsqueda")
	assert_eq(search.get_selected_text(), "be", "con el texto elegido para escribir encima")
	search.text = ""
	search.text_changed.emit("")
	search.text_submitted.emit("")
	await wait_frames(1)
	var focused := vp.gui_get_focus_owner()
	assert_true(focused != null and focused.get("project") != null, "Enter en la búsqueda baja a la lista")
	assert_eq(focused.project.name, "Beta", "a la seleccionada (la última agregada)")
	assert_true(screen.handle_shortcut(&"gm_refresh"))
	await wait_frames(2)
	assert_eq(vp.gui_get_focus_owner().get("project").name, "Beta", "F5 no pierde el foco ni la selección")
	assert_true(screen.handle_shortcut(&"gm_delete"))
	var dialog: ConfirmationDialog = screen.get_node("%RemoveDialog")
	assert_true(dialog.visible, "Supr pide confirmación")
	dialog.hide()
	assert_false(screen.handle_shortcut(&"gm_next_tab"), "lo que no es de la pantalla no lo toma")
	screen.remove_project(screen.selected.path)
	screen.remove_project(screen.entries[0].path)
	assert_false(screen.handle_shortcut(&"gm_delete"), "sin selección, Supr no hace nada")


func test_missing_project_stays_listed() -> void:
	var l := ProjectList.new()
	l.add(root.path_join("borrado"))
	l.save(CFG)
	screen.load_list()
	assert_eq(screen.entries.size(), 1)
	assert_true(screen.entries[0].missing)
	assert_eq((screen.get_node("%Placeholder") as Control).visible, false)
