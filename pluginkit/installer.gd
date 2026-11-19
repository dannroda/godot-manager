extends RefCounted
## Instalar el zip de un plugin en un proyecto, en dos pasos: plan() dice qué haría sin tocar nada
## y apply() lo hace. Sigue al instalador del editor: saca la carpeta raíz del zip (salvo que sea
## addons/) y, si el zip trae addons/, instala solo eso (suelen traer demos, README y hasta un
## project.godot). Las rutas son relativas al proyecto, con "/".
##
## Nunca pisa sin avisar: un archivo que ya existe y no es de este plugin, o que es de este plugin
## pero se cambió a mano (su hash no es el del lock), es un conflicto; con `force` se pisa igual.
## Si el archivo que existe es idéntico al del zip, se adopta sin escribirlo (un plugin instalado a
## mano en la misma versión no da conflicto).


## `entry`: lo que el lock tiene de este plugin ({} si es nuevo): `files` ruta -> sha256.
## `owners`: ruta -> nombre de los archivos de los demás plugins del lock.
## `{files: [{zip, path, sha256, write}], stale: [path], conflicts: [{path, reason, owner}],
## skipped: [path], folders: [path], plugins: [path de plugin.cfg], error}`.
## reason: "exists" (no es de nadie), "modified" (de este plugin, cambiado a mano), "owned" (de otro).
static func plan(zip_path: String, project: String, entry: Dictionary = {}, owners: Dictionary = {}) -> Dictionary:
	var result := {"files": [], "stale": [], "conflicts": [], "skipped": [], "folders": [], "plugins": [], "error": ""}
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		result.error = "bad_zip"
		return result
	var names := reader.get_files()
	var root := _toplevel(names)
	if root == "addons/":
		root = ""
	var entries := []
	var has_addons := false
	for name: String in names:
		if name.ends_with("/"):
			continue
		var relative := name.trim_prefix(root).replace("\\", "/")
		# Con «\\», una unidad («C:») o «..» una entrada saldría del proyecto.
		if not safe_path(relative):
			continue
		has_addons = has_addons or relative.begins_with("addons/")
		entries.append([name, relative])
	if entries.is_empty():
		reader.close()
		result.error = "empty_zip"
		return result
	var owned: Dictionary = entry.get("files", {})
	var new_paths := {}
	for pair: Array in entries:
		var relative: String = pair[1]
		if has_addons and not relative.begins_with("addons/"):
			result.skipped.append(relative)
			continue
		var data := reader.read_file(pair[0])
		var hash := sha256_bytes(data)
		var target := project.path_join(relative)
		var write := true
		if FileAccess.file_exists(target):
			var current := FileAccess.get_sha256(target)
			if current == hash:
				write = false
			elif owners.has(relative):
				result.conflicts.append({"path": relative, "reason": "owned", "owner": owners[relative]})
			elif not owned.has(relative):
				result.conflicts.append({"path": relative, "reason": "exists", "owner": ""})
			elif owned[relative] != current:
				result.conflicts.append({"path": relative, "reason": "modified", "owner": ""})
		new_paths[relative] = true
		result.files.append({"zip": pair[0], "path": relative, "sha256": hash, "write": write})
		if relative.begins_with("addons/") and relative.get_file() == "plugin.cfg":
			result.plugins.append(relative)
		var folder := addon_folder(relative)
		if not folder.is_empty() and not folder in result.folders:
			result.folders.append(folder)
	reader.close()
	for relative: String in owned:
		if new_paths.has(relative) or not FileAccess.file_exists(project.path_join(relative)):
			continue
		result.stale.append(relative)
		if FileAccess.get_sha256(project.path_join(relative)) != owned[relative]:
			result.conflicts.append({"path": relative, "reason": "modified", "owner": ""})
	return result


## Escribe lo que el plan dice y borra lo que la versión nueva ya no trae (con lo que el editor
## generó al lado: .import y .uid). `{written, removed, error}`; error "write_failed" con `path`.
static func apply(zip_path: String, project: String, the_plan: Dictionary) -> Dictionary:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return {"written": 0, "removed": 0, "error": "bad_zip"}
	var written := 0
	for file: Dictionary in the_plan.files:
		if not file.write:
			continue
		var target := project.path_join(file.path)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var out := FileAccess.open(target, FileAccess.WRITE)
		if out == null:
			reader.close()
			return {"written": written, "removed": 0, "error": "write_failed", "path": file.path}
		out.store_buffer(reader.read_file(file.zip))
		out.close()
		written += 1
	reader.close()
	var removed := delete_files(project, the_plan.stale)
	prune_dirs(project, the_plan.folders)
	return {"written": written, "removed": removed, "error": ""}


## Borra estos archivos del proyecto y lo que el editor generó para ellos. Cuántos borró.
static func delete_files(project: String, paths: Array) -> int:
	var removed := 0
	for relative: String in paths:
		var target := project.path_join(relative)
		if FileAccess.file_exists(target) and DirAccess.remove_absolute(target) == OK:
			removed += 1
		for extra: String in [".import", ".uid"]:
			if not paths.has(relative + extra) and FileAccess.file_exists(target + extra):
				DirAccess.remove_absolute(target + extra)
	return removed


## Borra las carpetas vacías dentro de cada una de `folders` (y la carpeta misma si quedó vacía).
static func prune_dirs(project: String, folders: Array) -> void:
	for folder: String in folders:
		_prune(project.path_join(folder))


static func _prune(dir: String) -> bool:
	var access := DirAccess.open(dir)
	if access == null:
		return false
	access.include_hidden = true
	var empty := access.get_files().is_empty()
	for sub: String in access.get_directories():
		if not _prune(dir.path_join(sub)):
			empty = false
	if empty:
		DirAccess.remove_absolute(dir)
	return empty


## sha256 de cada archivo que el plan deja en el proyecto (lo que va al lock).
static func file_hashes(the_plan: Dictionary) -> Dictionary:
	var result := {}
	for file: Dictionary in the_plan.files:
		result[file.path] = file.sha256
	return result


## Archivos del lock que se cambiaron a mano o se borraron: `{modified: [path], missing: [path]}`.
static func check(project: String, entry: Dictionary) -> Dictionary:
	var result := {"modified": [], "missing": []}
	var files: Dictionary = entry.get("files", {})
	for relative: String in files:
		var target := project.path_join(relative)
		if not FileAccess.file_exists(target):
			result.missing.append(relative)
		elif FileAccess.get_sha256(target) != files[relative]:
			result.modified.append(relative)
	return result


## "addons/x" de "addons/x/y.gd"; "" si no está dentro de una carpeta de addons/.
static func addon_folder(relative: String) -> String:
	var parts := relative.split("/")
	if parts.size() < 3 or parts[0] != "addons":
		return ""
	return "addons/" + parts[1]


static func safe_path(relative: String) -> bool:
	return not (relative.is_empty() or relative.begins_with("/") or relative.contains(":")
		or ".." in relative.split("/") or relative.is_absolute_path())


static func sha256_bytes(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	if not data.is_empty():
		ctx.update(data)
	return ctx.finish().hex_encode()


## Carpeta raíz común del zip ("carpeta/") o "" si no hay una.
static func _toplevel(names: PackedStringArray) -> String:
	if names.is_empty():
		return ""
	var slash := names[0].find("/")
	if slash < 0:
		return ""
	var root := names[0].left(slash + 1)
	for name: String in names:
		if not name.begins_with(root):
			return ""
	return root
