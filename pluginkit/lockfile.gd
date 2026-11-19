extends RefCounted
## Los dos archivos de la raíz del proyecto (JSON, para que los lea cualquier herramienta):
##
## plugins.json, lo que se pide (se edita a mano o con las herramientas):
##   {"plugins": {"<nombre>": {"source": "store:pub/slug", "version": "1.2.0", "prerelease": true}}}
##   `version` fija esa versión (el plugin queda congelado); sin `version` se sigue la más nueva que
##   anda con el Godot del proyecto. `prerelease` deja pasar pre-releases.
##
## plugins.lock, lo que quedó instalado (lo escriben las herramientas):
##   {"schema": 1, "plugins": {"<nombre>": {"source", "version", "release", "sha256", "url",
##    "godot_min", "godot_max", "folders": ["addons/x"], "files": {"addons/x/a.gd": "<sha256>"}}}}
##   `release` es el id de la release en su fuente; `sha256` es el del zip; `url` solo se guarda
##   si no vence (GitHub). Con los hashes de los archivos se sabe si alguien los cambió a mano.

const MANIFEST := "plugins.json"
const LOCK := "plugins.lock"
const SCHEMA := 1


static func read_manifest(project: String) -> Dictionary:
	return _plugins(_read(project.path_join(MANIFEST)))


static func read_lock(project: String) -> Dictionary:
	return _plugins(_read(project.path_join(LOCK)))


## Si plugins.json no se pudo leer (existe pero no es JSON válido): "" si está bien.
static func manifest_error(project: String) -> String:
	var path := project.path_join(MANIFEST)
	if FileAccess.file_exists(path) and not _read(path) is Dictionary:
		return "bad_manifest"
	return ""


## Guarda los pedidos manteniendo lo demás que tenga el archivo (claves que agregue otra
## herramienta).
static func write_manifest(project: String, plugins: Dictionary) -> int:
	var path := project.path_join(MANIFEST)
	var data: Variant = _read(path)
	var doc: Dictionary = data if data is Dictionary else {}
	doc["plugins"] = plugins
	return _write(path, doc)


static func write_lock(project: String, plugins: Dictionary) -> int:
	var path := project.path_join(LOCK)
	if plugins.is_empty():
		return DirAccess.remove_absolute(path) if FileAccess.file_exists(path) else OK
	return _write(path, {"schema": SCHEMA, "plugins": plugins})


## ruta -> nombre de todos los archivos del lock, salvo los de `except`.
static func owners(lock: Dictionary, except: String = "") -> Dictionary:
	var result := {}
	for name: String in lock:
		if name == except:
			continue
		for path: String in lock[name].get("files", {}):
			result[path] = name
	return result


## El plugin del lock que instaló `addons/<folder>` ("" si ninguno).
static func owner_of_folder(lock: Dictionary, folder: String) -> String:
	var wanted := "addons/" + folder.trim_prefix("addons/").trim_suffix("/")
	for name: String in lock:
		if wanted in lock[name].get("folders", []):
			return name
	return ""


static func _plugins(data: Variant) -> Dictionary:
	if not data is Dictionary or not data.get("plugins") is Dictionary:
		return {}
	var result := {}
	for name: Variant in data.plugins:
		if data.plugins[name] is Dictionary:
			result[str(name)] = data.plugins[name]
	return result


static func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	return json.data


static func _write(path: String, doc: Dictionary) -> int:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(doc, "  ", true) + "\n")
	file.close()
	return OK
