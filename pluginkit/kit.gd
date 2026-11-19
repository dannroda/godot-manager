extends RefCounted
## Plugins de un proyecto a partir de plugins.json y plugins.lock (ver lockfile.gd). La usan la
## CLI de godot-manager (con cli.gd, en un Godot sin ventana) y addons como godot-agent (desde el
## editor). No depende del editor: el proyecto es una carpeta del disco y quien la usa se encarga
## de activar plugins y de que el editor vea los archivos nuevos.
##
## Cada operación devuelve un Dictionary; si falla, con `error` (un código) y `details`.
## Códigos: invalid_source, no_connection, not_found, rate_limited, http_error, bad_response,
## bad_zip, empty_zip, write_failed, checksum_mismatch, conflicts, no_release, no_such_version,
## incompatible, not_in_manifest, not_installed, name_taken, bad_manifest, bad_preset,
## lock_write_failed.

const Versions := preload("versions.gd")
const Sources := preload("sources.gd")
const Installer := preload("installer.gd")
const Lockfile := preload("lockfile.gd")

const VERSION := "0.1.0"

## Avisos de progreso: ("download", {name, version}), ("install", {name, version, files}),
## ("check", {name}), ("remove", {name}).
signal progress(what: String, data: Dictionary)

## Carpeta del proyecto (la de project.godot), ruta del disco.
var project: String
## Versión de Godot del proyecto ("4.5.1", "4.8-beta3"); "" si no se sabe (no se filtra).
var godot := ""
## Objeto con get_json(url) y download(url, path) (ver http.gd).
var http: Object
## Dónde bajar los zips.
var temp_dir: String
## Pisar conflictos e instalar versiones que no andan con `godot`.
var force := false


func _init(project_dir: String, http_client: Object, temp: String) -> void:
	project = project_dir
	http = http_client
	temp_dir = temp


func search(query: String, page: int = 1) -> Dictionary:
	var response: Dictionary = await http.get_json(Sources.store_search_url(query, page, godot))
	if not response.error.is_empty():
		return _fail(response.error, {"status": response.status})
	var data: Variant = response.data
	var count := int(str(data.get("count", 0))) if data is Dictionary else 0
	return {"assets": Sources.store_hits(data), "count": count, "pages": ceili(count / 24.0)}


## Agrega un plugin a plugins.json y lo instala. `spec`: fuente con @versión opcional (fija esa
## versión). Con `pin`, fija la versión que se instale.
func add(spec: String, name: String = "", pin: bool = false, prerelease: bool = false) -> Dictionary:
	var bad := Lockfile.manifest_error(project)
	if not bad.is_empty():
		return _fail(bad)
	var parts := Sources.split_version(spec)
	var source := Sources.parse(parts[0])
	if source.has("error"):
		return _fail("invalid_source", {"source": spec})
	if name.is_empty():
		name = source.name
	var manifest := Lockfile.read_manifest(project)
	if manifest.has(name) and manifest[name].get("source", "") != source.source:
		return _fail("name_taken", {"name": name, "source": manifest[name].get("source", "")})
	var listed := await _releases(source)
	if listed.has("error"):
		return listed
	var release := _choose(listed.releases, parts[1], prerelease)
	if release.has("error"):
		release.details["name"] = name
		return release
	var lock := Lockfile.read_lock(project)
	var done := await _install(name, source, release, lock.get(name, {}), "")
	if done.has("error"):
		return done
	var wanted := {"source": source.source}
	if pin or not parts[1].is_empty():
		wanted["version"] = release.version
	if prerelease:
		wanted["prerelease"] = true
	manifest[name] = wanted
	if Lockfile.write_manifest(project, manifest) != OK:
		return _fail("write_failed", {"path": Lockfile.MANIFEST})
	done["pinned"] = wanted.has("version")
	return done


## Deja el proyecto como dicen plugins.json y plugins.lock: lo del lock se baja en esa misma
## versión (y se verifica su sha256); lo que no está en el lock, o pide otra versión, se resuelve.
## `{installed: [...], ok: [name], extra: [name]}`; extra: en el lock pero no en plugins.json.
func install() -> Dictionary:
	var bad := Lockfile.manifest_error(project)
	if not bad.is_empty():
		return _fail(bad)
	var manifest := Lockfile.read_manifest(project)
	var lock := Lockfile.read_lock(project)
	var installed := []
	var ok := []
	for name: String in _sorted(manifest):
		var wanted: Dictionary = manifest[name]
		var source := Sources.parse(str(wanted.get("source", "")))
		if source.has("error"):
			return _fail("invalid_source", {"name": name, "source": wanted.get("source", "")})
		var requested := str(wanted.get("version", ""))
		var locked: Dictionary = lock.get(name, {})
		progress.emit("check", {"name": name})
		var listed: Dictionary
		var release: Dictionary
		var expected := ""
		if not locked.is_empty() and locked.get("source") == source.source and (requested.is_empty() or Versions.same(requested, str(locked.version))):
			var state := Installer.check(project, locked)
			if state.missing.is_empty() and state.modified.is_empty():
				ok.append(name)
				continue
			listed = await _releases(source)
			if listed.has("error"):
				return _with_name(listed, name)
			release = Sources.by_id(listed.releases, str(locked.get("release", "")))
			if release.is_empty():
				return _fail("no_such_version", {"name": name, "version": locked.version, "available": _versions(listed.releases)})
			expected = str(locked.get("sha256", ""))
		else:
			listed = await _releases(source)
			if listed.has("error"):
				return _with_name(listed, name)
			release = _choose(listed.releases, requested, bool(wanted.get("prerelease", false)))
			if release.has("error"):
				release.details["name"] = name
				return release
		var done := await _install(name, source, release, locked, expected)
		if done.has("error"):
			return done
		installed.append(done)
		lock = Lockfile.read_lock(project)
	var extra := []
	for name: String in _sorted(lock):
		if not manifest.has(name):
			extra.append(name)
	return {"installed": installed, "ok": ok, "extra": extra}


## Versiones nuevas que andan con el Godot del proyecto. Para cada plugin instalado:
## `{name, source, version, latest, newer, pinned, incompatible, blocked}`; `blocked` es la más
## nueva que no anda con este Godot ({version, godot_min, godot_max}) si es más nueva que `latest`;
## `incompatible`, si la instalada ya no anda con este Godot.
func outdated() -> Dictionary:
	var manifest := Lockfile.read_manifest(project)
	var lock := Lockfile.read_lock(project)
	var result := []
	for name: String in _sorted(manifest):
		var locked: Dictionary = lock.get(name, {})
		if locked.is_empty():
			continue
		var source := Sources.parse(str(locked.get("source", "")))
		if source.has("error"):
			continue
		progress.emit("check", {"name": name})
		var listed := await _releases(source)
		if listed.has("error"):
			return _with_name(listed, name)
		var prerelease := bool(manifest[name].get("prerelease", false))
		var latest := Sources.pick(listed.releases, godot, "", prerelease)
		var newest := Sources.pick(listed.releases, "", "", prerelease)
		var current := str(locked.version)
		var item := {
			"name": name, "source": source.source, "version": current,
			"latest": latest.get("version", ""),
			"newer": not latest.is_empty() and Versions.compare(latest.version, current) > 0,
			"pinned": manifest[name].has("version"),
			"incompatible": not Versions.godot_in_range(godot, str(locked.get("godot_min", "")), str(locked.get("godot_max", ""))),
			"blocked": {},
		}
		if not newest.is_empty() and Versions.compare(newest.version, item.latest if not item.latest.is_empty() else current) > 0:
			item.blocked = {"version": newest.version, "godot_min": newest.godot_min, "godot_max": newest.godot_max}
		result.append(item)
	return {"plugins": result, "godot": godot}


## Actualiza a la versión más nueva que anda con este Godot. Sin `names`, todos los que no están
## fijados; un plugin fijado no se actualiza (hay que soltarlo con unpin o fijar otra versión).
## `{updated: [...], skipped: [{name, reason}]}`; reason: pinned, latest, not_installed.
func update(names: PackedStringArray = PackedStringArray()) -> Dictionary:
	var manifest := Lockfile.read_manifest(project)
	for name: String in names:
		if not manifest.has(name):
			return _fail("not_in_manifest", {"name": name})
	var updated := []
	var skipped := []
	for name: String in (Array(names) if not names.is_empty() else _sorted(manifest)):
		var wanted: Dictionary = manifest[name]
		var lock := Lockfile.read_lock(project)
		var locked: Dictionary = lock.get(name, {})
		if wanted.has("version"):
			skipped.append({"name": name, "reason": "pinned", "version": wanted.version})
			continue
		if locked.is_empty():
			skipped.append({"name": name, "reason": "not_installed"})
			continue
		var source := Sources.parse(str(wanted.get("source", "")))
		if source.has("error"):
			return _fail("invalid_source", {"name": name, "source": wanted.get("source", "")})
		progress.emit("check", {"name": name})
		var listed := await _releases(source)
		if listed.has("error"):
			return _with_name(listed, name)
		var latest := Sources.pick(listed.releases, godot, "", bool(wanted.get("prerelease", false)))
		if latest.is_empty() or Versions.compare(latest.version, str(locked.version)) <= 0:
			skipped.append({"name": name, "reason": "latest", "version": locked.version})
			continue
		var done := await _install(name, source, latest, locked, "")
		if done.has("error"):
			return done
		updated.append(done)
	return {"updated": updated, "skipped": skipped}


## Fija un plugin: en la versión instalada o, con `version`, en esa (y la instala).
func pin(name: String, version: String = "") -> Dictionary:
	var manifest := Lockfile.read_manifest(project)
	if not manifest.has(name):
		return _fail("not_in_manifest", {"name": name})
	var locked: Dictionary = Lockfile.read_lock(project).get(name, {})
	var result := {"name": name, "installed": {}}
	if version.is_empty() or (not locked.is_empty() and Versions.same(version, str(locked.version))):
		if locked.is_empty():
			return _fail("not_installed", {"name": name})
		version = str(locked.version)
	else:
		var source := Sources.parse(str(manifest[name].get("source", "")))
		if source.has("error"):
			return _fail("invalid_source", {"name": name, "source": manifest[name].get("source", "")})
		var listed := await _releases(source)
		if listed.has("error"):
			return _with_name(listed, name)
		var release := _choose(listed.releases, version, true)
		if release.has("error"):
			release.details["name"] = name
			return release
		var done := await _install(name, source, release, locked, "")
		if done.has("error"):
			return done
		result.installed = done
		version = release.version
	manifest[name]["version"] = version
	if Lockfile.write_manifest(project, manifest) != OK:
		return _fail("write_failed", {"path": Lockfile.MANIFEST})
	result["version"] = version
	return result


## Suelta un plugin fijado: vuelve a seguir la versión más nueva (no instala nada).
func unpin(name: String) -> Dictionary:
	var manifest := Lockfile.read_manifest(project)
	if not manifest.has(name):
		return _fail("not_in_manifest", {"name": name})
	var was := str(manifest[name].get("version", ""))
	manifest[name].erase("version")
	if Lockfile.write_manifest(project, manifest) != OK:
		return _fail("write_failed", {"path": Lockfile.MANIFEST})
	return {"name": name, "was": was}


## Borra los archivos que instaló el plugin y lo saca de plugins.json y plugins.lock. Los
## plugin.cfg que tenía van en `plugins` (quien llama los desactiva antes, en project.godot).
func remove(name: String) -> Dictionary:
	var manifest := Lockfile.read_manifest(project)
	var lock := Lockfile.read_lock(project)
	if not lock.has(name) and not manifest.has(name):
		return _fail("not_in_manifest", {"name": name})
	var entry: Dictionary = lock.get(name, {})
	var files: Array = entry.get("files", {}).keys()
	progress.emit("remove", {"name": name})
	var state := Installer.check(project, entry)
	var removed := Installer.delete_files(project, files)
	Installer.prune_dirs(project, entry.get("folders", []))
	lock.erase(name)
	manifest.erase(name)
	if Lockfile.write_lock(project, lock) != OK:
		return _fail("lock_write_failed")
	Lockfile.write_manifest(project, manifest)
	var plugins := files.filter(func(path: String) -> bool: return path.get_file() == "plugin.cfg")
	var left := []
	for folder: String in entry.get("folders", []):
		if DirAccess.dir_exists_absolute(project.path_join(folder)):
			left.append(folder)
	return {"name": name, "removed": removed, "modified": state.modified, "plugins": plugins, "left": left}


## Lo que dicen plugins.json y plugins.lock, y si los archivos siguen como se instalaron:
## `[{name, source, requested, version, pinned, installed, modified: n, missing: n, folders}]`.
func status() -> Dictionary:
	var manifest := Lockfile.read_manifest(project)
	var lock := Lockfile.read_lock(project)
	var names := _sorted(manifest)
	for name: String in _sorted(lock):
		if not name in names:
			names.append(name)
	var result := []
	for name: String in names:
		var wanted: Dictionary = manifest.get(name, {})
		var locked: Dictionary = lock.get(name, {})
		var state := Installer.check(project, locked)
		result.append({
			"name": name, "source": str(wanted.get("source", locked.get("source", ""))),
			"requested": str(wanted.get("version", "")), "version": str(locked.get("version", "")),
			"pinned": wanted.has("version"), "in_manifest": not wanted.is_empty(),
			"installed": not locked.is_empty(), "modified": state.modified.size(),
			"missing": state.missing.size(), "folders": locked.get("folders", []),
		})
	return {"plugins": result, "manifest_error": Lockfile.manifest_error(project)}


# --- presets -------------------------------------------------------------------------------------
# Un preset es un archivo con la forma de plugins.json: los plugins que uno suele usar, para
# sumarlos a un proyecto de una vez.

## Suma los plugins del preset de `path` a plugins.json (los que ya están quedan como estaban) e
## instala. `{added: [name], kept: [name], installed: [...], ok: [name], extra: [name]}`.
func apply(path: String) -> Dictionary:
	var bad := Lockfile.file_error(path)
	if not bad.is_empty() or not FileAccess.file_exists(path):
		return _fail("bad_preset", {"path": path})
	bad = Lockfile.manifest_error(project)
	if not bad.is_empty():
		return _fail(bad)
	var preset := Lockfile.read_plugins(path)
	var manifest := Lockfile.read_manifest(project)
	var added := []
	var kept := []
	for name: String in _sorted(preset):
		var wanted: Dictionary = preset[name]
		if manifest.has(name):
			if manifest[name].get("source", "") != wanted.get("source", ""):
				return _fail("name_taken", {"name": name, "source": manifest[name].get("source", "")})
			kept.append(name)
			continue
		manifest[name] = wanted.duplicate()
		added.append(name)
	if Lockfile.write_manifest(project, manifest) != OK:
		return _fail("write_failed", {"path": Lockfile.MANIFEST})
	var done := await install()
	if done.has("error"):
		return done
	done["added"] = added
	done["kept"] = kept
	return done


## Agrega fuentes (con @versión opcional, que la fija) al preset de `path`; lo crea si no existe.
## No baja nada. `{added: [name], plugins: {...}}`.
func preset_add(path: String, specs: PackedStringArray, prerelease: bool = false) -> Dictionary:
	var bad := Lockfile.file_error(path)
	if not bad.is_empty():
		return _fail("bad_preset", {"path": path})
	var plugins := Lockfile.read_plugins(path)
	var added := []
	for spec: String in specs:
		var parts := Sources.split_version(spec)
		var source := Sources.parse(parts[0])
		if source.has("error"):
			return _fail("invalid_source", {"source": spec})
		var entry := {"source": source.source}
		if not parts[1].is_empty():
			entry["version"] = parts[1]
		if prerelease:
			entry["prerelease"] = true
		plugins[source.name] = entry
		added.append(source.name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if Lockfile.write_plugins(path, plugins) != OK:
		return _fail("write_failed", {"path": path})
	return {"added": added, "plugins": plugins}


# --- interno -------------------------------------------------------------------------------------

func _releases(source: Dictionary) -> Dictionary:
	var response: Dictionary = await http.get_json(Sources.releases_url(source))
	if not response.error.is_empty():
		return _fail(response.error, {"source": source.source, "status": response.status})
	if not response.data is Array:
		return _fail("bad_response", {"source": source.source})
	return {"releases": Sources.releases(source, response.data)}


## La release pedida (o la que corresponde) con el error que toca si no hay.
func _choose(list: Array, version: String, prerelease: bool) -> Dictionary:
	var release := Sources.pick(list, godot, version, prerelease)
	if release.is_empty():
		if not version.is_empty():
			return _fail("no_such_version", {"version": version, "available": _versions(list)})
		var newest := Sources.pick(list, "", "", true)
		return _fail("no_release", {"godot": godot, "newest": newest.get("version", ""),
			"godot_min": newest.get("godot_min", ""), "godot_max": newest.get("godot_max", "")})
	if not force and not Versions.godot_in_range(godot, release.godot_min, release.godot_max):
		return _fail("incompatible", {"version": release.version, "godot": godot,
			"godot_min": release.godot_min, "godot_max": release.godot_max})
	return release


func _install(name: String, source: Dictionary, release: Dictionary, previous: Dictionary, expected_sha: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(temp_dir)
	var zip := temp_dir.path_join("%s-%d.zip" % [name.validate_filename(), Time.get_ticks_usec()])
	progress.emit("download", {"name": name, "version": release.version})
	var got: Dictionary = await http.download(release.url, zip)
	if not got.error.is_empty():
		DirAccess.remove_absolute(zip)
		return _fail(got.error, {"name": name, "source": source.source, "status": got.status})
	var sha := FileAccess.get_sha256(zip)
	if not expected_sha.is_empty() and sha != expected_sha and not force:
		DirAccess.remove_absolute(zip)
		return _fail("checksum_mismatch", {"name": name, "version": release.version, "expected": expected_sha, "got": sha})
	var lock := Lockfile.read_lock(project)
	var the_plan := Installer.plan(zip, project, previous, Lockfile.owners(lock, name))
	if not the_plan.error.is_empty():
		DirAccess.remove_absolute(zip)
		return _fail(the_plan.error, {"name": name, "version": release.version})
	if not the_plan.conflicts.is_empty() and not force:
		DirAccess.remove_absolute(zip)
		return _fail("conflicts", {"name": name, "version": release.version, "conflicts": the_plan.conflicts})
	progress.emit("install", {"name": name, "version": release.version, "files": the_plan.files.size()})
	var applied := Installer.apply(zip, project, the_plan)
	DirAccess.remove_absolute(zip)
	if not applied.error.is_empty():
		return _fail(applied.error, {"name": name, "path": applied.get("path", "")})
	var entry := {
		"source": source.source, "version": release.version, "release": release.id, "sha256": sha,
		"godot_min": release.godot_min, "godot_max": release.godot_max,
		"folders": the_plan.folders, "files": Installer.file_hashes(the_plan),
	}
	if source.kind == "github":
		entry["url"] = release.url
	lock[name] = entry
	if Lockfile.write_lock(project, lock) != OK:
		return _fail("lock_write_failed")
	return {
		"name": name, "source": source.source, "version": release.version,
		"from": str(previous.get("version", "")), "written": applied.written, "removed": applied.removed,
		"folders": the_plan.folders, "plugins": the_plan.plugins, "skipped": the_plan.skipped.size(),
		"overwritten": the_plan.conflicts,
	}


static func _fail(code: String, details: Dictionary = {}) -> Dictionary:
	return {"error": code, "details": details}


static func _with_name(failure: Dictionary, name: String) -> Dictionary:
	failure.details["name"] = name
	return failure


static func _versions(list: Array) -> Array:
	return list.map(func(r: Dictionary) -> String: return r.version)


static func _sorted(dict: Dictionary) -> Array:
	var keys := dict.keys()
	keys.sort()
	return keys
