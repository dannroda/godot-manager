extends TestCase
## Lista de proyectos: lectura de project.godot, escaneo, persistencia, filtro.

const CFG := "user://test_projects.cfg"

var root := ""


func before_each() -> void:
	root = ProjectSettings.globalize_path("user://test_project_tree")
	_remove_tree(root)
	DirAccess.make_dir_recursive_absolute(root)


func after_each() -> void:
	_remove_tree(root)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))


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


## Crea `<root>/<rel>/project.godot` con ese contenido.
func _project(rel: String, text := "config_version=5\n") -> String:
	var dir := root.path_join(rel)
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("project.godot"), FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return dir


const FULL := """; Engine configuration file.
config_version=5

[application]

config/name="Mi Juego"
config/features=PackedStringArray("4.8", "GL Compatibility")
config/icon="res://art/icon.svg"

[input]

saltar={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":32,"physical_keycode":0,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
"""


func test_read_full_project() -> void:
	var dir := _project("juego", FULL)
	var e := ProjectEntry.read(dir + "/")
	assert_eq(e.path, dir, "sin barra final")
	assert_eq(e.name, "Mi Juego")
	assert_eq(e.features, PackedStringArray(["4.8", "GL Compatibility"]))
	assert_eq(e.created_with(), "4.8")
	assert_eq(e.icon_path, dir.path_join("art/icon.svg"))
	assert_false(e.missing)
	assert_false(e.unreadable)
	assert_true(e.modified > 0)


func test_read_without_name_or_features() -> void:
	var e := ProjectEntry.read(_project("sin_nombre"))
	assert_eq(e.name, "sin_nombre", "sin config/name, la carpeta")
	assert_eq(e.created_with(), "")
	assert_eq(e.icon_path, "")
	var g3 := ProjectEntry.read(_project("viejo", "config_version=4\n[application]\nconfig/name=\"Viejo\"\n"))
	assert_eq(g3.created_with(), "3.x")


func test_read_missing_and_broken() -> void:
	var e := ProjectEntry.read(root.path_join("no_existe"))
	assert_true(e.missing)
	assert_eq(e.name, "no_existe")
	var b := ProjectEntry.read(_project("roto", "[application\nconfig/name=\"x"))
	assert_true(b.unreadable)
	assert_eq(b.name, "roto")


func test_icon_paths() -> void:
	assert_eq(ProjectEntry.resolve_res("/p", "res://icon.png"), "/p/icon.png")
	assert_eq(ProjectEntry.resolve_res("/p", "uid://b1234"), "", "uid sin resolver")
	assert_eq(ProjectEntry.resolve_res("/p", "res://../fuera.png"), "", "no se sale del proyecto")
	assert_eq(ProjectEntry.resolve_res("/p", ""), "")


func test_scan_nested_skips_hidden_and_depth() -> void:
	var a := _project("a")
	var nested := _project("a/sub/b")
	var deep := _project("x/1/2/3/hondo")
	_project("a/.godot/editor/fantasma")
	_project(".git/oculto")
	_project("web/node_modules/paquete")
	DirAccess.make_dir_recursive_absolute(root.path_join("vacia/nada"))
	var found := ProjectList.scan(root)
	found.sort()
	assert_eq(found, PackedStringArray([a, nested, deep]), "anidados sí; .godot, .git y node_modules no")
	var shallow := ProjectList.scan(root, 2)
	shallow.sort()
	assert_eq(shallow, PackedStringArray([a]), "con profundidad 2 no llega a a/sub/b ni a x/1/2/3/hondo")
	assert_eq(ProjectList.scan(a, 0), PackedStringArray([a]), "la carpeta elegida cuenta")
	assert_eq(ProjectList.scan(root.path_join("no_existe")), PackedStringArray())


func test_add_remove_dedup() -> void:
	var l := ProjectList.new()
	assert_true(l.add("/home/u/juego/"))
	assert_false(l.add("/home/u/juego"), "misma carpeta con o sin barra")
	assert_false(l.add("/home/u/otro/../juego"))
	assert_eq(l.add_all(PackedStringArray(["/home/u/juego", "/home/u/b", "/home/u/c"])), 2)
	assert_true(l.remove("/home/u/b/"))
	assert_false(l.remove("/home/u/b"))
	assert_eq(l.paths, PackedStringArray(["/home/u/juego", "/home/u/c"]))
	assert_false(l.add("  "))


func test_windows_paths_normalized() -> void:
	assert_eq(ProjectEntry.normalize("C:\\Users\\u\\juego\\"), "C:/Users/u/juego")
	assert_eq(ProjectEntry.normalize("C:/"), "C:/")
	assert_eq(ProjectEntry.normalize("c:\\Juegos\\Mi Juego"), "C:/Juegos/Mi Juego", "la unidad, en mayúscula")
	assert_eq(ProjectEntry.normalize("/home/u/a:b"), "/home/u/a:b")


func test_save_and_load() -> void:
	var l := ProjectList.new()
	l.add_all(PackedStringArray(["/a/uno", "/b/dos con espacio"]))
	l.last_scan_dir = "/a"
	l.sort = ProjectList.Sort.NAME
	assert_eq(l.save(CFG), OK)
	var r := ProjectList.load_from(CFG)
	assert_eq(r.paths, l.paths)
	assert_eq(r.last_scan_dir, "/a")
	assert_eq(r.sort, ProjectList.Sort.NAME)
	var empty := ProjectList.load_from("user://no_existe_456.cfg")
	assert_eq(empty.paths.size(), 0)
	assert_eq(empty.sort, ProjectList.Sort.MODIFIED)


func _entry(n: String, p: String, mod: int) -> ProjectEntry:
	var e := ProjectEntry.new()
	e.name = n
	e.path = p
	e.modified = mod
	return e


func test_filter_and_sort() -> void:
	var list: Array[ProjectEntry] = [_entry("beta", "/z/b", 10), _entry("Alfa", "/y/a", 30),
		_entry("juego 10", "/x/j10", 20), _entry("juego 2", "/x/j2", 20)]
	var names := func(out: Array[ProjectEntry]) -> PackedStringArray:
		var n := PackedStringArray()
		for e in out:
			n.append(e.name)
		return n
	assert_eq(names.call(ProjectList.apply(list, "", ProjectList.Sort.NAME)),
		PackedStringArray(["Alfa", "beta", "juego 2", "juego 10"]), "orden natural y sin mayúsculas")
	assert_eq(names.call(ProjectList.apply(list, "", ProjectList.Sort.MODIFIED)),
		PackedStringArray(["Alfa", "juego 2", "juego 10", "beta"]), "más reciente arriba; empate por nombre")
	assert_eq(names.call(ProjectList.apply(list, "", ProjectList.Sort.PATH)),
		PackedStringArray(["juego 2", "juego 10", "Alfa", "beta"]))
	assert_eq(names.call(ProjectList.apply(list, "JUEGO", ProjectList.Sort.NAME)),
		PackedStringArray(["juego 2", "juego 10"]))
	assert_eq(names.call(ProjectList.apply(list, "/y/", ProjectList.Sort.NAME)), PackedStringArray(["Alfa"]),
		"busca también en la ruta")
