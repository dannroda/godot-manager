extends TestCase


static func _fixture(name: String) -> String:
	return FileAccess.get_file_as_string("res://tests/fixtures/" + name)


func test_parse_list_real_output() -> void:
	var r := GmParse.parse_list(_fixture("list.json"))
	if not assert_true(r.ok, str(r.error)):
		return
	var versions: Array = r.value
	assert_eq(versions.size(), 6)
	var def: Array = versions.filter(func(v: InstalledVersion) -> bool: return v.is_default)
	assert_eq(def.size(), 1)
	var v: InstalledVersion = def[0]
	assert_eq(v.name, "4.7.2-stable")
	assert_eq(v.template_platforms, PackedStringArray(["linux", "windows"]))
	assert_true(v.has_templates())
	var mono: InstalledVersion = versions[2]
	assert_true(mono.mono)
	assert_eq(mono.tag, "4.7.2-stable")
	assert_true((versions[5] as InstalledVersion).debug_symbols)


func test_parse_list_old_cli_missing_fields() -> void:
	var r := GmParse.parse_list('{"default":"b","versions":[{"name":"a","path":"/a"},{"name":"b","path":"/b"}]}')
	if not assert_true(r.ok, str(r.error)):
		return
	var b: InstalledVersion = r.value[1]
	assert_true(b.is_default, "default sale de la raíz si falta en la versión")
	assert_eq(b.tag, "")
	assert_eq(b.template_platforms, PackedStringArray())


func test_parse_list_empty() -> void:
	var r := GmParse.parse_list('{"default":"","versions":[]}')
	assert_true(r.ok)
	assert_eq((r.value as Array).size(), 0)


func test_parse_list_wrong_types() -> void:
	var r := GmParse.parse_list('{"versions":[{"name":3,"path":"/a","mono":"si"}]}')
	assert_false(r.ok)
	assert_eq(r.error.code, CliError.BAD_OUTPUT)
	assert_has(r.error.message, "'name' no es texto")
	assert_has(r.error.message, "'mono' no es true/false")
	assert_has(r.error.message, "\"mono\":\"si\"", "incluye el texto original")


func test_parse_list_missing_required() -> void:
	var r := GmParse.parse_list('{"versions":[{"path":"/a"}]}')
	assert_false(r.ok)
	assert_has(r.error.message, "falta 'name'")
	assert_false(GmParse.parse_list('{}').ok, "sin 'versions'")
	assert_false(GmParse.parse_list('[]').ok, "lista en vez de objeto")


func test_broken_json_and_empty() -> void:
	var r := GmParse.parse_list('{"versions": [')
	assert_false(r.ok)
	assert_eq(r.error.code, CliError.BAD_OUTPUT)
	assert_has(r.error.message, "JSON inválido")
	var empty := GmParse.parse_which("  \n")
	assert_false(empty.ok)
	assert_has(empty.error.message, "no devolvió nada")
	var plain := GmParse.parse_which("panic: runtime error")
	assert_false(plain.ok)
	assert_has(plain.error.message, "panic: runtime error")


func test_long_output_is_trimmed() -> void:
	var r := GmParse.parse_which("x".repeat(5000))
	assert_false(r.ok)
	assert_true(r.error.message.length() < 500, "largo %d: %s" % [r.error.message.length(), r.error.message.left(120)])
	assert_eq((r.error.extra["original"] as String).length(), 5000, "el original completo queda en extra")


func test_parse_remote_real_output() -> void:
	var r := GmParse.parse_remote(_fixture("list_remote.json"))
	if not assert_true(r.ok, str(r.error)):
		return
	var list: Array = r.value
	assert_eq(list.size(), 4)
	var beta: RemoteVersion = list[0]
	assert_eq(beta.tag, "4.8-beta3")
	assert_true(beta.prerelease)
	assert_eq(beta.templates_size, 1354701894)
	assert_eq(typeof(beta.editor_size), TYPE_INT)
	var old: RemoteVersion = list[3]
	assert_false(old.editor, "3.x en Linux: sin editor")
	assert_eq(old.editor_size, 0)


func test_parse_remote_old_cli() -> void:
	var r := GmParse.parse_remote('[{"tag":"4.3-stable","prerelease":false,"published_at":"2024-08-15T00:00:00Z"}]')
	if not assert_true(r.ok, str(r.error)):
		return
	var v: RemoteVersion = r.value[0]
	assert_true(v.editor, "sin el campo, se asume que hay editor")
	assert_true(v.mono and v.debug_symbols and v.templates and v.mono_templates,
		"sin los campos de C.7 todo queda habilitado y decide el CLI")
	assert_eq(v.editor_size, 0)
	assert_eq(v.url, "", "sin url (anterior a 2.2)")


func test_parse_remote_url() -> void:
	var r := GmParse.parse_remote('[{"tag":"4.3-stable","url":"https://github.com/godotengine/godot-builds/releases/tag/4.3-stable"}]')
	if assert_true(r.ok, str(r.error)):
		assert_eq((r.value[0] as RemoteVersion).url, "https://github.com/godotengine/godot-builds/releases/tag/4.3-stable")


func test_parse_remote_bad_size() -> void:
	var r := GmParse.parse_remote('[{"tag":"x","editor_size":1.5}]')
	assert_false(r.ok)
	assert_has(r.error.message, "'editor_size' no es un entero")


func test_parse_which_real_output() -> void:
	var r := GmParse.parse_which(_fixture("which.json"))
	if not assert_true(r.ok, str(r.error)):
		return
	var res: Resolution = r.value
	assert_eq(res.version, "4.8-beta3")
	assert_false(res.is_from_default())
	assert_true(res.source.ends_with(".godot-version"))


func test_cli_errors_verbatim() -> void:
	var lines := _fixture("errors.txt").strip_edges().split("\n")
	var r := GmParse.parse_list(lines[0])
	assert_false(r.ok)
	assert_eq(r.error.code, "not_installed")
	assert_eq(r.error.message, "'9.9-nope' no esta instalada (ver 'godot-manager list')")
	var u := GmParse.parse_ok(lines[1])
	assert_eq(u.error.code, "unknown_command")


func test_error_extra_fields() -> void:
	var r := GmParse.parse_which('{"error":{"code":"not_installed","message":"m","version":"4.1","source":"/p/.godot-version"}}')
	assert_false(r.ok)
	assert_eq(r.error.extra, {"version": "4.1", "source": "/p/.godot-version"})


func test_parse_ok() -> void:
	var r := GmParse.parse_ok('{"ok":true,"version":"4.3","removed_templates":false}')
	assert_true(r.ok)
	assert_eq(r.value["version"], "4.3")
	assert_false(GmParse.parse_ok('{"version":"4.3"}').ok, "sin ok:true")


func test_parse_events() -> void:
	var step: CliEvent = GmParse.parse_event('{"event":"step","message":"Descargando"}').value
	assert_eq(step.kind, CliEvent.Kind.STEP)
	assert_eq(step.message, "Descargando")
	var dl: CliEvent = GmParse.parse_event('{"event":"download","file":"a.zip","done":50,"total":200}').value
	assert_eq(dl.kind, CliEvent.Kind.DOWNLOAD)
	assert_eq(dl.progress(), 0.25)
	var unknown_total: CliEvent = GmParse.parse_event('{"event":"download","file":"a","done":5,"total":0}').value
	assert_eq(unknown_total.progress(), -1.0)
	var warn: CliEvent = GmParse.parse_event('{"event":"warn","message":"ojo"}').value
	assert_eq(warn.kind, CliEvent.Kind.WARN)
	var done: CliEvent = GmParse.parse_event('{"event":"done","version":"4.3","platforms":["linux"]}').value
	assert_true(done.is_final())
	assert_eq(done.data["platforms"], ["linux"])
	var err: CliEvent = GmParse.parse_event('{"event":"error","code":"checksum","message":"no coincide","file":"x"}').value
	assert_eq(err.kind, CliEvent.Kind.ERROR)
	assert_eq(err.error.code, "checksum")
	assert_eq(err.error.extra, {"file": "x"})


func test_parse_event_plain_error_and_garbage() -> void:
	var r := GmParse.parse_event('{"error":{"code":"invalid_args","message":"falta la version"}}')
	assert_true(r.ok)
	assert_eq((r.value as CliEvent).error.code, "invalid_args")
	assert_false(GmParse.parse_event("Descargando 50%").ok)
	var unknown := GmParse.parse_event('{"event":"nuevo"}')
	assert_false(unknown.ok)
	assert_has(unknown.error.message, "evento desconocido 'nuevo'")


static func _done_job(code: int, out: String, err := "") -> CliJob:
	var j := CliJob.new(["--json", "x"], CliJob.Kind.READ)
	j.exit_code = code
	j.stdout = out
	j.stderr = err
	j.state = CliJob.State.DONE
	return j


func test_job_error_sources() -> void:
	assert_eq(GmParse.job_error(_done_job(0, '{"ok":true}\n')), null, "bien: sin error")
	var json := GmParse.job_error(_done_job(1, '{"error":{"code":"not_installed","message":"\'9.9\' no esta instalada"}}\n'))
	assert_eq(json.code, "not_installed")
	assert_eq(json.message, "'9.9' no esta instalada")
	var ev := GmParse.job_error(_done_job(1, '{"event":"step","message":"a"}\n{"event":"error","code":"network","message":"sin red"}\n'))
	assert_eq(ev.code, "network")
	assert_eq(ev.message, "sin red")
	var raw := GmParse.job_error(_done_job(2, "", "Error: algo salió mal\n"))
	assert_eq(raw.message, "algo salió mal", "stderr sin el prefijo Error:")
	var none := GmParse.job_error(_done_job(3, ""))
	assert_has(none.message, "código 3")
	var cancelled := _done_job(-1, "")
	cancelled.cancelled = true
	assert_eq(GmParse.job_error(cancelled), null, "cancelado: sin aviso")


func test_version_sorting() -> void:
	assert_eq(GmParse.version_numbers("4.8.1-beta3"), PackedInt32Array([4, 8, 1]))
	assert_eq(GmParse.version_numbers("3.6-stable"), PackedInt32Array([3, 6, 0]))
	assert_true(GmParse.is_newer("4.8-beta3", "4.8-beta2"))
	assert_true(GmParse.is_newer("4.8-rc1", "4.8-beta3"))
	assert_true(GmParse.is_newer("4.8-stable", "4.8-rc2"))
	assert_true(GmParse.is_newer("4.7.2-stable", "4.7-stable"))
	assert_true(GmParse.is_newer("4.10-stable", "4.9-stable"))
	assert_true(GmParse.is_newer("3.6.3-stable", "3.6-dev2"))
	assert_false(GmParse.is_newer("4.3-stable", "4.3-stable"))
	var tags := ["3.6.3-stable", "4.8-beta2", "4.7.2-stable", "4.8-beta3", "4.8-dev1"]
	tags.sort_custom(GmParse.is_newer)
	assert_eq(tags, ["4.8-beta3", "4.8-beta2", "4.8-dev1", "4.7.2-stable", "3.6.3-stable"])


func test_parse_plugins() -> void:
	var text := """{"project": "/p", "plugins": [
		{"id": "good", "name": "Good", "description": "d", "author": "Ana", "version": "1.2",
		 "script": "plugin.gd", "path": "/p/addons/good", "enabled": true, "missing": false, "problems": []},
		{"id": "gone", "name": "", "path": "/p/addons/gone", "enabled": true, "missing": true,
		 "problems": ["está activo en project.godot pero la carpeta no existe"]}]}"""
	var r := GmParse.parse_plugins(text)
	if not assert_true(r.ok, str(r.error)):
		return
	assert_eq(r.value.size(), 2)
	var good: ProjectPlugin = r.value[0]
	assert_eq(good.display_name(), "Good")
	assert_eq(good.version, "1.2")
	assert_true(good.enabled)
	assert_false(good.has_problems())
	var gone: ProjectPlugin = r.value[1]
	assert_eq(gone.display_name(), "gone", "sin name usa la carpeta")
	assert_true(gone.missing)
	assert_true(gone.has_problems())


func test_parse_plugins_errors() -> void:
	assert_eq(GmParse.parse_plugins("""{"error": {"code": "not_a_project", "message": "x"}}""").error.code, "not_a_project")
	assert_eq(GmParse.parse_plugins("""{"project": "/p"}""").error.code, CliError.BAD_OUTPUT)
	assert_eq(GmParse.parse_plugins("""{"plugins": [{"name": "sin id"}]}""").error.code, CliError.BAD_OUTPUT)


func test_parse_outdated() -> void:
	var r := GmParse.parse_outdated('{"updates":[{"version":"4.5-stable","latest":"4.5.2-stable","installed":false,"url":"https://x"},{"version":"4.8-beta2-mono","latest":"4.8-beta4-mono","installed":true}]}')
	if not assert_true(r.ok, str(r.error)):
		return
	var ups: Array = r.value
	assert_eq(ups.size(), 2)
	assert_eq((ups[0] as VersionUpdate).latest, "4.5.2-stable")
	assert_eq((ups[0] as VersionUpdate).url, "https://x")
	assert_true((ups[1] as VersionUpdate).installed)
	assert_false(GmParse.parse_outdated('{"updates":[{"version":"x"}]}').ok, "falta latest")


func test_parse_prune() -> void:
	var r := GmParse.parse_prune('{"ok":true,"removed":false,"total":3000,"versions":[{"version":"4.3-stable","size":1000,"templates_dir":"/t/4.3.stable","templates_size":2000}]}')
	if not assert_true(r.ok, str(r.error)):
		return
	var rep: PruneReport = r.value
	assert_eq(rep.total, 3000)
	assert_false(rep.removed)
	assert_eq(rep.candidates.size(), 1)
	assert_eq(rep.candidates[0].templates_size, 2000)
	var e := GmParse.parse_prune('{"error":{"code":"needs_confirmation","message":"usa --yes"}}')
	assert_eq(e.error.code, "needs_confirmation")


func test_parse_path() -> void:
	var r := GmParse.parse_path('{"dir":"C:/gm","on_path":true,"target":"PATH del usuario","managed":""}')
	if not assert_true(r.ok, str(r.error)):
		return
	var st: PathStatus = r.value
	assert_true(st.on_path)
	assert_eq(st.target, "PATH del usuario")
	assert_eq(st.managed, "")


func test_parse_dirs() -> void:
	var r := GmParse.parse_dirs('{"godot_dir":"D:/gm","default_godot_dir":"C:/x/godot-manager","custom":true,"versions":"D:/gm/versions","templates":"C:/t"}')
	if not assert_true(r.ok, str(r.error)):
		return
	var d: Dictionary = r.value
	assert_eq(d.godot_dir, "D:/gm")
	assert_eq(d.default_godot_dir, "C:/x/godot-manager")
	assert_true(d.custom)
	assert_false(GmParse.parse_dirs('{"default_godot_dir":"x"}').ok, "falta godot_dir")


func test_parse_managed_plugins() -> void:
	var r := GmParse.parse_plugins('{"project":"/p","plugins":[{"id":"x","name":"X","path":"/p/addons/x","enabled":true,"managed":{"name":"x-plugin","source":"store:a/x","version":"v1.2","pinned":true}},{"id":"y","managed":null}],"pending":[{"name":"z","source":"github:a/z","version":"","pinned":false}]}')
	if not assert_true(r.ok, str(r.error)):
		return
	var list: Array = r.value
	assert_eq(list.size(), 3)
	var x: ProjectPlugin = list[0]
	assert_true(x.is_managed())
	assert_eq([x.managed_name, x.source, x.locked_version, x.pinned], ["x-plugin", "store:a/x", "v1.2", true])
	assert_false((list[1] as ProjectPlugin).is_managed(), "instalado a mano")
	var z: ProjectPlugin = list[2]
	assert_true(z.pending)
	assert_eq(z.display_name(), "z")


func test_parse_plugin_outdated() -> void:
	var r := GmParse.parse_plugin_outdated('{"ok":true,"godot":"4.5","plugins":[{"name":"dm","source":"store:n/dm","version":"v3.10.5","latest":"v3.10.5","newer":false,"pinned":false,"incompatible":false,"blocked":{"version":"v4.2.0","godot_min":"4.6","godot_max":""}},{"name":"ga","version":"v0.1.30","latest":"v0.1.32","newer":true,"pinned":true,"blocked":{}}]}')
	if not assert_true(r.ok, str(r.error)):
		return
	var list: Array = r.value
	var dm: PluginUpdate = list[0]
	assert_false(dm.newer)
	assert_eq(dm.blocked_version, "v4.2.0")
	assert_eq(dm.blocked_godot(), "Godot 4.6+")
	var ga: PluginUpdate = list[1]
	assert_true(ga.newer)
	assert_true(ga.pinned)
	assert_eq(ga.blocked_version, "")
	assert_eq(GmParse.parse_plugin_outdated('{"error":{"code":"network","message":"sin red"}}').error.code, "network")


func test_parse_plugin_search() -> void:
	var r := GmParse.parse_plugin_search('{"ok":true,"count":30,"pages":2,"assets":[{"source":"store:n/dm","name":"Dialogue Manager","publisher":"Nathan","description":"Diálogos","license":"MIT","score":62,"store_url":"https://s"}]}')
	if not assert_true(r.ok, str(r.error)):
		return
	assert_eq(r.value.pages, 2)
	var a: StoreAsset = r.value.assets[0]
	assert_eq([a.source, a.name, a.publisher, a.score], ["store:n/dm", "Dialogue Manager", "Nathan", 62])
	assert_false(GmParse.parse_plugin_search('{"ok":true,"assets":[{"name":"sin fuente"}]}').ok)


func test_parse_presets() -> void:
	var r := GmParse.parse_presets('{"dir":"/gm/presets","presets":[{"name":"mios","path":"/gm/presets/mios.json","plugins":[{"name":"a","source":"store:x/a","version":"v1"},{"name":"b","source":"github:x/b","version":""}]}]}')
	if not assert_true(r.ok, str(r.error)):
		return
	var p: PluginPreset = r.value[0]
	assert_eq(p.name, "mios")
	assert_eq(p.summary(), "a v1, b")
