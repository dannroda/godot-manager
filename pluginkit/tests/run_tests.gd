extends SceneTree
## Tests de la librería, sin red (un HTTP falso que sirve JSON y zips armados acá):
##   godot --headless --path pluginkit --script res://tests/run_tests.gd
## Sale con 0 si pasan todos.

const Versions := preload("../versions.gd")
const Sources := preload("../sources.gd")
const Installer := preload("../installer.gd")
const Lockfile := preload("../lockfile.gd")
const Kit := preload("../kit.gd")


## Contesta con lo que tenga cargado: `json[url]` o el zip `zips[url]` (ruta local).
class FakeHttp:
	var json := {}
	var zips := {}
	var asked := []

	func get_json(url: String) -> Dictionary:
		asked.append(url)
		if not json.has(url):
			return {"data": null, "error": "not_found", "status": 404}
		return {"data": json[url], "error": "", "status": 200}

	func download(url: String, path: String) -> Dictionary:
		asked.append(url)
		if not zips.has(url):
			return {"error": "not_found", "status": 404}
		DirAccess.copy_absolute(zips[url], path)
		return {"error": "", "status": 200}


var failures := 0
var checks := 0
var current := ""
var base := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	base = OS.get_cache_dir().path_join("godot-plugin-kit-tests-%d" % OS.get_process_id()).replace("\\", "/")
	_remove_tree(base)
	DirAccess.make_dir_recursive_absolute(base)
	for method: Dictionary in get_script().get_script_method_list():
		var name: String = method.name
		if name.begins_with("test_"):
			current = name
			await call(name)
	_remove_tree(base)
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(condition: bool, what: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL %s: %s" % [current, what])


func eq(got: Variant, want: Variant, what: String) -> void:
	check(got == want, "%s: got %s, want %s" % [what, var_to_str(got), var_to_str(want)])


# --- ayudas --------------------------------------------------------------------------------------

## Un zip con estos archivos (ruta -> texto).
func make_zip(name: String, files: Dictionary) -> String:
	var path := base.path_join(name)
	var packer := ZIPPacker.new()
	packer.open(path)
	for file: String in files:
		packer.start_file(file)
		packer.write_file(str(files[file]).to_utf8_buffer())
		packer.close_file()
	packer.close()
	return path


func make_project(name: String) -> String:
	var dir := base.path_join(name)
	DirAccess.make_dir_recursive_absolute(dir)
	FileAccess.open(dir.path_join("project.godot"), FileAccess.WRITE).store_string("config_version=5\n")
	return dir


func write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func store_release(id: int, version: String, url: String, low: Variant = null, high: Variant = null, stable := true) -> Dictionary:
	return {"id": float(id), "version": version, "download_url": url, "min_godot_version": low,
		"max_godot_version": high, "stable": stable, "created": "2026-01-01", "size": 0.1}


## Un Store falso con el asset pub/thing en v1.0.0 (Godot 4.3+) y v2.0.0 (Godot 4.6+).
func store_kit(project: String) -> Kit:
	var http := FakeHttp.new()
	http.json[Sources.STORE_API + "/releases/pub/thing/"] = [
		store_release(2, "v2.0.0", "https://x/thing-2.zip", "4.6"),
		store_release(1, "v1.0.0", "https://x/thing-1.zip", "4.3"),
	]
	http.zips["https://x/thing-1.zip"] = make_zip("thing-1.zip", {
		"thing-1.0.0/addons/thing/plugin.cfg": "[plugin]\nversion=\"1.0.0\"\n",
		"thing-1.0.0/addons/thing/main.gd": "v1",
		"thing-1.0.0/addons/thing/old.gd": "solo en v1",
		"thing-1.0.0/README.md": "readme",
	})
	http.zips["https://x/thing-2.zip"] = make_zip("thing-2.zip", {
		"addons/thing/plugin.cfg": "[plugin]\nversion=\"2.0.0\"\n",
		"addons/thing/main.gd": "v2",
	})
	var kit := Kit.new(project, http, base.path_join("tmp"))
	kit.godot = "4.6.1"
	return kit


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for file: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for sub: String in dir.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


# --- versiones y fuentes -------------------------------------------------------------------------

func test_compare_versions() -> void:
	eq(Versions.compare("v1.2.3", "1.2.3"), 0, "con y sin v")
	eq(Versions.compare("1.10.0", "1.9.9"), 1, "numérico, no texto")
	eq(Versions.compare("1.3.0-beta.1", "1.3.0"), -1, "pre-release antes")
	eq(Versions.compare("1.2", "1.2.0"), 0, "partes que faltan son 0")
	eq(Versions.godot_number("4.8-beta3"), "4.8", "número de 4.8-beta3")
	eq(Versions.godot_number("4.5.1-stable"), "4.5.1", "número de 4.5.1-stable")


func test_godot_range() -> void:
	check(Versions.godot_in_range("4.7.2", "4.6", "4.7"), "4.7.2 entra en un máximo 4.7")
	check(not Versions.godot_in_range("4.5.1", "4.6", ""), "4.5.1 no llega a 4.6")
	check(not Versions.godot_in_range("4.8-beta3", "", "4.7"), "4.8 pasa el máximo 4.7")
	check(Versions.godot_in_range("", "9.0", ""), "sin versión de Godot no se filtra")


func test_parse_sources() -> void:
	eq(Sources.parse("store:nathanhoad/dialogue-manager").source, "store:nathanhoad/dialogue-manager", "store:")
	eq(Sources.parse("nathanhoad/dialogue-manager").kind, "store", "sin prefijo es del Store")
	eq(Sources.parse("https://store.godotengine.org/asset/a/b/").source, "store:a/b", "URL del Store")
	var gh := Sources.parse("https://github.com/dannroda/godot-agent.git")
	eq(gh.source, "github:dannroda/godot-agent", "URL de GitHub")
	eq(gh.name, "godot-agent", "nombre")
	check(Sources.parse("nada").has("error"), "sin / es inválida")
	check(Sources.parse("a/../b").has("error"), "con .. es inválida")
	eq(Sources.split_version("github:a/b@v1.2"), PackedStringArray(["github:a/b", "v1.2"]), "fuente@versión")


func test_store_search() -> void:
	check(Sources.store_search_url("Dialogue ", 1, "").contains("query=dialogue&"), "texto en minúsculas")
	check(Sources.store_search_url("x", 1, "").contains("sort=relevance"), "con texto, por relevancia")
	check(Sources.store_search_url("", 2, "4.6.1").contains("sort=reviews_desc"), "sin texto, los mejor puntuados")
	check(Sources.store_search_url("", 2, "4.6.1").ends_with("&compatibility=4.6.1&page=2"), "Godot y página")
	var hits := Sources.store_hits({"hits": [
		{"asset": {"name": "Cam", "slug": "cam", "publisher": {"slug": "pub"}, "thumbnail": "https://x/t.webp",
			"tags": [{"slug": "3d", "display_name": "3D"}, {"slug": "tool", "display_name": "Tool"}]}},
		{"asset": {"name": "Sprites", "slug": "spr", "publisher": {"slug": "pub"}, "thumbnail": "/static/a.png",
			"tags": [{"slug": "2d", "display_name": "2D"}, {"slug": "pixelart", "display_name": "Pixel Art"}]}},
		{"asset": {"name": "Agua", "slug": "agua", "publisher": {"slug": "pub"}, "tags": []}},
	]})
	eq(hits.size(), 3, "los tres")
	eq(hits[0].tags, ["3D", "Tool"], "etiquetas con el nombre del Store")
	eq(hits[0].kind, "plugin", "con tool: trae código")
	eq(hits[1].kind, "content", "pixel art sin código: contenido")
	eq(hits[2].kind, "", "sin etiquetas: no se sabe")
	eq(hits[1].thumbnail, "https://store.godotengine.org/static/a.png", "miniatura con el dominio")
	eq(hits[2].thumbnail, "", "sin miniatura")
	eq(Sources.guess_kind(PackedStringArray(["pixelart", "importer"])), "plugin", "código gana")
	eq(Sources.guess_kind(PackedStringArray(["2d"]), "Open Duelyst Animated Sprites Spritesheets from the repo"), "content", "sin etiquetas claras: por las palabras")
	eq(Sources.guess_kind(PackedStringArray(["3d", "camera"]), "Phantom Camera A Camera addon for Godot 4"), "plugin", "addon en la descripción")
	eq(Sources.guess_kind(PackedStringArray(["2d"]), "Notebook of nodes"), "plugin", "palabra al principio: node(s)")
	eq(Sources.guess_kind(PackedStringArray(), "Agua"), "", "nada")


func test_pick_release() -> void:
	var list := Sources.store_releases([
		store_release(3, "v3.0.0-beta", "u3", "4.6", null, false),
		store_release(2, "v2.0.0", "u2", "4.6"),
		store_release(1, "v1.0.0", "u1", "4.3", "4.5"),
	])
	eq(list[1].id, "2", "id como texto")
	eq(Sources.pick(list, "4.6.1").version, "v2.0.0", "estable más nueva que anda")
	eq(Sources.pick(list, "4.6.1", "", true).version, "v3.0.0-beta", "con pre-releases")
	eq(Sources.pick(list, "4.4").version, "v1.0.0", "la que anda con 4.4")
	check(Sources.pick(list, "4.2").is_empty(), "ninguna anda con 4.2")
	eq(Sources.pick(list, "4.2", "1.0.0").version, "v1.0.0", "la pedida aunque no ande")
	var only_pre := Sources.store_releases([store_release(5, "v0.2.0-rc", "u", null, null, false)])
	eq(Sources.pick(only_pre, "4.6").version, "v0.2.0-rc", "sin estables, la pre-release")


func test_github_releases() -> void:
	var list := Sources.github_releases([
		{"tag_name": "v0.1.9", "prerelease": false, "assets": [{"name": "x.zip", "browser_download_url": "z9"}]},
		{"tag_name": "v0.1.10", "prerelease": true, "assets": [], "zipball_url": "zb10"},
		{"tag_name": "v0.2.0", "draft": true, "assets": [{"name": "x.zip", "browser_download_url": "z"}]},
	])
	eq(list.size(), 2, "sin borradores")
	eq(list[0].version, "v0.1.10", "ordenadas por versión")
	eq(list[0].url, "zb10", "sin .zip adjunto, el del código")
	check(not list[0].stable, "pre-release")


# --- instalación ---------------------------------------------------------------------------------

func test_plan_strips_root_and_keeps_addons() -> void:
	var project := make_project("plan")
	var zip := make_zip("plan.zip", {"x-1/addons/x/plugin.cfg": "cfg", "x-1/addons/x/a.gd": "a", "x-1/demo/scene.tscn": "demo"})
	var p := Installer.plan(zip, project)
	eq(p.files.map(func(f: Dictionary) -> String: return f.path), ["addons/x/plugin.cfg", "addons/x/a.gd"], "solo addons/, sin la raíz")
	eq(p.skipped, ["demo/scene.tscn"], "lo de afuera queda")
	eq(p.folders, ["addons/x"], "carpetas")
	eq(p.plugins, ["addons/x/plugin.cfg"], "plugin.cfg")


func test_plan_without_addons_keeps_paths() -> void:
	var project := make_project("pack")
	var zip := make_zip("pack.zip", {"Loops/a.wav": "a", "Loops/Retro/b.wav": "b", "Sprites/hero.tres": "res://Sprites/hero.png", "LICENCE.pdf": "l"})
	var p := Installer.plan(zip, project)
	eq(p.files.size(), 4, "todo, con las rutas del zip (como Godot: no se rompen sus res://)")
	eq(p.folders, ["Loops", "Sprites"], "carpetas de primer nivel, para la lista y para desinstalar")
	eq(p.skipped, [], "nada afuera")


func test_plan_skips_unsafe_paths() -> void:
	var zip := make_zip("unsafe.zip", {"addons/x/../../evil.gd": "x", "addons/x/ok.gd": "ok", "C:/evil.gd": "x"})
	var p := Installer.plan(zip, make_project("unsafe"))
	eq(p.files.map(func(f: Dictionary) -> String: return f.path), ["addons/x/ok.gd"], "sin rutas que salen del proyecto")


func test_plan_conflicts() -> void:
	var project := make_project("conflicts")
	var zip := make_zip("c.zip", {"addons/x/same.gd": "igual", "addons/x/other.gd": "nuevo", "addons/x/mine.gd": "nuevo", "addons/x/theirs.gd": "nuevo"})
	write(project.path_join("addons/x/same.gd"), "igual")
	write(project.path_join("addons/x/other.gd"), "de alguien")
	write(project.path_join("addons/x/mine.gd"), "tocado a mano")
	write(project.path_join("addons/x/theirs.gd"), "de y")
	write(project.path_join("addons/x/gone.gd"), "ya no viene")
	var entry := {"files": {"addons/x/mine.gd": Installer.sha256_bytes("original".to_utf8_buffer()),
		"addons/x/gone.gd": Installer.sha256_bytes("ya no viene".to_utf8_buffer())}}
	var p := Installer.plan(zip, project, entry, {"addons/x/theirs.gd": "y"})
	var reasons := {}
	for c: Dictionary in p.conflicts:
		reasons[c.path] = c.reason
	eq(reasons, {"addons/x/other.gd": "exists", "addons/x/mine.gd": "modified", "addons/x/theirs.gd": "owned"}, "conflictos")
	check(not p.files[0].write, "el idéntico se adopta sin escribir")
	eq(p.stale, ["addons/x/gone.gd"], "lo que la versión nueva no trae")


# --- operaciones ---------------------------------------------------------------------------------

func test_add_picks_compatible_and_writes_lock() -> void:
	var project := make_project("add")
	var kit := store_kit(project)
	kit.godot = "4.5"
	var done: Dictionary = await kit.add("pub/thing")
	eq(done.get("error", ""), "", "sin error")
	eq(done.version, "v1.0.0", "la que anda con 4.5")
	eq(read(project.path_join("addons/thing/main.gd")), "v1", "instalado")
	check(not FileAccess.file_exists(project.path_join("README.md")), "sin lo de afuera de addons/")
	var lock := Lockfile.read_lock(project)
	eq(lock.thing.release, "1", "id de la release")
	eq(lock.thing.godot_min, "4.3", "rango de Godot")
	check(not lock.thing.has("url"), "sin el link que vence")
	eq(Lockfile.read_manifest(project), {"thing": {"source": "store:pub/thing"}}, "plugins.json")


func test_add_pinned_and_incompatible() -> void:
	var project := make_project("pinned")
	var kit := store_kit(project)
	kit.godot = "4.5"
	var refused: Dictionary = await kit.add("pub/thing@2.0.0")
	eq(refused.get("error", ""), "incompatible", "2.0.0 pide 4.6")
	kit.godot = "4.6"
	var done: Dictionary = await kit.add("pub/thing@1.0.0")
	eq(done.version, "v1.0.0", "la pedida")
	eq(Lockfile.read_manifest(project).thing.get("version"), "v1.0.0", "queda fijada")
	var up: Dictionary = await kit.update()
	eq(up.skipped[0].reason, "pinned", "fijada no se actualiza")


func test_no_release_for_old_godot() -> void:
	var kit := store_kit(make_project("old"))
	kit.godot = "4.2"
	var refused: Dictionary = await kit.add("pub/thing")
	eq(refused.get("error", ""), "no_release", "ninguna anda con 4.2")
	eq(refused.details.godot_min, "4.6", "dice qué pide la más nueva")


func test_outdated_and_update() -> void:
	var project := make_project("update")
	var kit := store_kit(project)
	kit.godot = "4.5"
	await kit.add("pub/thing")
	var report: Dictionary = await kit.outdated()
	check(not report.plugins[0].newer, "con 4.5 no hay una nueva que ande")
	eq(report.plugins[0].blocked.version, "v2.0.0", "la que no anda")
	kit.godot = "4.6"
	report = await kit.outdated()
	check(report.plugins[0].newer, "con 4.6 sí")
	var up: Dictionary = await kit.update()
	eq(up.updated[0].from, "v1.0.0", "desde")
	eq(up.updated[0].version, "v2.0.0", "hasta")
	eq(read(project.path_join("addons/thing/main.gd")), "v2", "reemplazado")
	check(not FileAccess.file_exists(project.path_join("addons/thing/old.gd")), "borra lo que ya no viene")


func test_update_refuses_local_changes() -> void:
	var project := make_project("modified")
	var kit := store_kit(project)
	kit.godot = "4.5"
	await kit.add("pub/thing")
	write(project.path_join("addons/thing/main.gd"), "cambio mío")
	kit.godot = "4.6"
	var refused: Dictionary = await kit.update()
	eq(refused.get("error", ""), "conflicts", "no pisa lo cambiado")
	eq(read(project.path_join("addons/thing/main.gd")), "cambio mío", "sin tocar")
	kit.force = true
	var done: Dictionary = await kit.update()
	eq(done.updated[0].overwritten.size(), 1, "con force, avisa lo que pisó")


func test_install_from_lock() -> void:
	var project := make_project("install")
	var kit := store_kit(project)
	kit.godot = "4.5"
	await kit.add("pub/thing")
	var ok: Dictionary = await kit.install()
	eq(ok.ok, ["thing"], "ya estaba")
	_remove_tree(project.path_join("addons"))
	kit.godot = "4.6"  # el lock manda, aunque ahora ande una más nueva
	var done: Dictionary = await kit.install()
	eq(done.installed[0].version, "v1.0.0", "la del lock")
	var lock := Lockfile.read_lock(project)
	lock.thing.sha256 = "0".repeat(64)
	Lockfile.write_lock(project, lock)
	_remove_tree(project.path_join("addons"))
	var refused: Dictionary = await kit.install()
	eq(refused.get("error", ""), "checksum_mismatch", "el zip no es el del lock")


func test_pin_unpin_remove() -> void:
	var project := make_project("pin")
	var kit := store_kit(project)
	await kit.add("pub/thing")
	var pinned: Dictionary = await kit.pin("thing", "1.0.0")
	eq(pinned.version, "v1.0.0", "fija otra versión y la instala")
	eq(read(project.path_join("addons/thing/main.gd")), "v1", "instalada")
	var loose: Dictionary = kit.unpin("thing")
	eq(loose.was, "v1.0.0", "soltada")
	check(not Lockfile.read_manifest(project).thing.has("version"), "sin versión")
	write(project.path_join("addons/thing/main.gd.uid"), "uid://abc")
	var gone: Dictionary = kit.remove("thing")
	eq(gone.plugins, ["addons/thing/plugin.cfg"], "plugin.cfg para desactivar")
	check(not DirAccess.dir_exists_absolute(project.path_join("addons/thing")), "carpeta borrada, con lo que generó el editor")
	eq(Lockfile.read_manifest(project), {}, "fuera de plugins.json")
	check(not FileAccess.file_exists(project.path_join(Lockfile.LOCK)), "sin lock vacío")


func test_presets() -> void:
	var project := make_project("preset")
	var kit := store_kit(project)
	var preset := base.path_join("presets/base.json")
	var made: Dictionary = kit.preset_add(preset, PackedStringArray(["pub/thing@1.0.0", "github:me/tool"]))
	eq(made.added, ["thing", "tool"], "agregados")
	eq(Lockfile.read_plugins(preset).thing, {"source": "store:pub/thing", "version": "1.0.0"}, "con @versión queda fijado")
	check(kit.preset_add(preset, PackedStringArray(["nada"])).has("error"), "fuente inválida")
	kit.preset_add(preset, PackedStringArray([]))
	var only_thing := base.path_join("presets/thing.json")
	kit.preset_add(only_thing, PackedStringArray(["pub/thing@1.0.0"]))
	Lockfile.write_manifest(project, {"mine": {"source": "store:me/mine"}})
	var applied: Dictionary = await kit.apply(only_thing)
	# mine no está en el Store falso: install falla en él, pero el preset ya quedó anotado
	eq(applied.get("error", ""), "not_found", "lo que falta de antes también se instala")
	eq(Lockfile.read_manifest(project).keys().size(), 2, "sumado al plugins.json que había")
	Lockfile.write_manifest(project, {})
	applied = await kit.apply(only_thing)
	eq(applied.added, ["thing"], "agregado")
	eq(applied.installed[0].version, "v1.0.0", "en la versión del preset")
	applied = await kit.apply(only_thing)
	eq(applied.kept, ["thing"], "la segunda vez ya estaba")
	eq(applied.ok, ["thing"], "y no se reinstala")
	Lockfile.write_manifest(project, {"thing": {"source": "github:otro/thing"}})
	eq((await kit.apply(only_thing)).get("error", ""), "name_taken", "mismo nombre, otra fuente")
	eq((await kit.apply(base.path_join("no-existe.json"))).get("error", ""), "bad_preset", "preset que no existe")


func test_github_source_keeps_url() -> void:
	var project := make_project("github")
	var http := FakeHttp.new()
	http.json[Sources.GITHUB_API + "/repos/me/tool/releases?per_page=100"] = [
		{"tag_name": "v0.2.0", "prerelease": true, "assets": [{"name": "tool-v0.2.0.zip", "browser_download_url": "https://gh/tool.zip"}]},
	]
	http.zips["https://gh/tool.zip"] = make_zip("tool.zip", {"addons/tool/plugin.cfg": "cfg"})
	var kit := Kit.new(project, http, base.path_join("tmp"))
	var done: Dictionary = await kit.add("github:me/tool", "", true)
	eq(done.version, "v0.2.0", "la pre-release, que es la única")
	eq(Lockfile.read_lock(project).tool.url, "https://gh/tool.zip", "guarda el link")
	eq(Lockfile.read_manifest(project).tool.version, "v0.2.0", "--pin")
