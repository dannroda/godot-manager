class_name ProjectList
extends RefCounted
## Las carpetas de proyectos de la lista, guardadas en `user://projects.cfg`
## (propia: no se lee ni se escribe la del Project Manager), más el escaneo y
## el filtro/orden. Sin UI, para testearla sola.

const PATH := "user://projects.cfg"
## Hasta cuántos niveles debajo de la carpeta elegida busca el escaneo.
const SCAN_DEPTH := 5
## Carpetas que el escaneo no recorre (además de las que empiezan con punto,
## como .godot y .git).
const SKIP_DIRS: PackedStringArray = ["node_modules", "__pycache__"]

enum Sort { NAME, MODIFIED, PATH }

const SORT_LABELS := {
	Sort.MODIFIED: "Última modificación",
	Sort.NAME: "Nombre",
	Sort.PATH: "Ruta",
}

var paths := PackedStringArray()
## Última carpeta escaneada, para abrir ahí el selector la próxima vez.
var last_scan_dir := ""
var sort := Sort.MODIFIED


## Agrega la carpeta si no estaba. Devuelve si la agregó.
func add(dir: String) -> bool:
	var p := ProjectEntry.normalize(dir)
	if p.is_empty() or has(p):
		return false
	paths.append(p)
	return true


## Agrega varias; devuelve cuántas eran nuevas.
func add_all(dirs: PackedStringArray) -> int:
	var added := 0
	for d in dirs:
		if add(d):
			added += 1
	return added


func remove(dir: String) -> bool:
	var i := paths.find(ProjectEntry.normalize(dir))
	if i < 0:
		return false
	paths.remove_at(i)
	return true


func has(dir: String) -> bool:
	return ProjectEntry.normalize(dir) in paths


func save(path := PATH) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("projects", "paths", paths)
	cfg.set_value("projects", "last_scan_dir", last_scan_dir)
	cfg.set_value("projects", "sort", int(sort))
	return cfg.save(path)


## Carga la lista; si falta o está rota, vacía.
static func load_from(path := PATH) -> ProjectList:
	var l := ProjectList.new()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return l
	var saved: Variant = cfg.get_value("projects", "paths", PackedStringArray())
	if saved is PackedStringArray:
		l.add_all(saved)
	l.last_scan_dir = str(cfg.get_value("projects", "last_scan_dir", ""))
	var s := int(cfg.get_value("projects", "sort", Sort.MODIFIED))
	if s in Sort.values():
		l.sort = s as Sort
	return l


## Carpetas con project.godot debajo de `root` (incluida), hasta `max_depth`
## niveles. Sigue buscando dentro de un proyecto (puede haber proyectos
## anidados, como esta UI dentro del repo del CLI). No toca nada de la escena:
## se puede correr en un Thread.
static func scan(root: String, max_depth := SCAN_DEPTH) -> PackedStringArray:
	var found := PackedStringArray()
	_scan_dir(ProjectEntry.normalize(root), max_depth, found)
	return found


static func _scan_dir(dir: String, depth_left: int, found: PackedStringArray) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	if da.file_exists(ProjectEntry.PROJECT_FILE):
		found.append(dir)
	if depth_left <= 0:
		return
	da.include_hidden = false
	da.include_navigational = false
	for sub in da.get_directories():
		if sub.begins_with(".") or sub in SKIP_DIRS:
			continue
		# Un enlace a una carpeta de arriba haría un ciclo: el tope de
		# profundidad lo corta, pero mejor no seguir enlaces.
		if da.is_link(dir.path_join(sub)):
			continue
		_scan_dir(dir.path_join(sub), depth_left - 1, found)


## Dónde guarda su lista el Project Manager de Godot en este sistema.
static func pm_config_path() -> String:
	match OS.get_name():
		"Windows":
			return OS.get_environment("APPDATA").path_join("Godot/projects.cfg")
		"macOS":
			return OS.get_environment("HOME").path_join("Library/Application Support/Godot/projects.cfg")
	var data := OS.get_environment("XDG_DATA_HOME")
	if data.is_empty():
		data = OS.get_environment("HOME").path_join(".local/share")
	return data.path_join("godot/projects.cfg")


## Las rutas de la lista del Project Manager (cada sección del cfg es una).
## Solo lee. `existing` = las que todavía tienen project.godot; `gone` = las
## demás. Si el archivo no está o no se puede leer, las dos vacías.
static func read_pm_list(path: String) -> Dictionary:
	var out := {"existing": PackedStringArray(), "gone": PackedStringArray()}
	var cfg := ConfigFile.new()
	if not FileAccess.file_exists(path) or cfg.load(path) != OK:
		return out
	for section in cfg.get_sections():
		var dir := ProjectEntry.normalize(section)
		if dir.is_empty():
			continue
		if FileAccess.file_exists(dir.path_join(ProjectEntry.PROJECT_FILE)):
			out["existing"].append(dir)
		else:
			out["gone"].append(dir)
	return out


## Las que coinciden con `query` (nombre o ruta, sin mayúsculas), ordenadas.
static func apply(entries: Array[ProjectEntry], query: String, by: Sort) -> Array[ProjectEntry]:
	var q := query.strip_edges().to_lower()
	var out: Array[ProjectEntry] = []
	for e in entries:
		if q.is_empty() or e.name.to_lower().contains(q) or e.path.to_lower().contains(q):
			out.append(e)
	match by:
		Sort.NAME:
			out.sort_custom(func(a: ProjectEntry, b: ProjectEntry) -> bool:
				return _by_name(a, b))
		Sort.PATH:
			out.sort_custom(func(a: ProjectEntry, b: ProjectEntry) -> bool:
				return a.path.naturalnocasecmp_to(b.path) < 0)
		_:
			out.sort_custom(func(a: ProjectEntry, b: ProjectEntry) -> bool:
				if a.modified != b.modified:
					return a.modified > b.modified
				return _by_name(a, b))
	return out


static func _by_name(a: ProjectEntry, b: ProjectEntry) -> bool:
	var c := a.name.naturalnocasecmp_to(b.name)
	if c != 0:
		return c < 0
	return a.path < b.path
