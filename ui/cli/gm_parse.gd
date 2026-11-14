class_name GmParse
extends RefCounted
## JSON del CLI → clases tipadas. Nunca falla con un crash: si la salida no es
## la esperada devuelve un GmResult con error `bad_output` y el texto original
## (recortado). Los campos nuevos del CLI que falten toman un valor por
## defecto, así un CLI más viejo sigue funcionando.

const MAX_ORIGINAL := 300
const MIN_CLI_MAJOR := 2
## Error propio: el binario no es un godot-manager 2.x.
const OLD_CLI := "old_cli"

const STAGES := {"dev": 0, "alpha": 1, "beta": 2, "rc": 3, "stable": 4}


## `list` → Array[InstalledVersion].
static func parse_list(text: String) -> GmResult:
	var root := _parse_json(text)
	if not root.ok:
		return root
	if not root.value is Dictionary:
		return _bad("se esperaba un objeto con 'versions'", text)
	var d: Dictionary = root.value
	var problems: Array[String] = []
	var default_name := _str(d, "default", problems, "")
	var out: Array[InstalledVersion] = []
	var items := _arr(d, "versions", problems, true)
	for i in items.size():
		if not items[i] is Dictionary:
			problems.append("versions[%d] no es un objeto" % i)
			continue
		var item: Dictionary = items[i]
		var v := InstalledVersion.new()
		v.name = _str(item, "name", problems, null)
		v.path = _str(item, "path", problems, null)
		v.is_default = _bool(item, "default", problems, v.name == default_name and not v.name.is_empty())
		v.mono = _bool(item, "mono", problems, false)
		v.debug_symbols = _bool(item, "debug_symbols", problems, false)
		v.tag = _str(item, "tag", problems, "")
		v.custom = _bool(item, "custom", problems, false)
		v.templates_dir = _str(item, "templates_dir", problems, "")
		v.template_platforms = _str_list(item, "template_platforms", problems)
		out.append(v)
	if not problems.is_empty():
		return _bad("; ".join(problems), text)
	return GmResult.success(out)


## `list-remote` → Array[RemoteVersion], en el orden del CLI.
static func parse_remote(text: String) -> GmResult:
	var root := _parse_json(text)
	if not root.ok:
		return root
	if not root.value is Array:
		return _bad("se esperaba una lista de releases", text)
	var items: Array = root.value
	var problems: Array[String] = []
	var out: Array[RemoteVersion] = []
	for i in items.size():
		if not items[i] is Dictionary:
			problems.append("[%d] no es un objeto" % i)
			continue
		var item: Dictionary = items[i]
		var r := RemoteVersion.new()
		r.tag = _str(item, "tag", problems, null)
		r.prerelease = _bool(item, "prerelease", problems, false)
		r.published_at = _str(item, "published_at", problems, "")
		# Sin el campo (CLI anterior a C.7) no se sabe: se asume que sí, la UI
		# deja la opción habilitada y, si no existe, lo dice el CLI.
		r.editor = _bool(item, "editor", problems, true)
		r.mono = _bool(item, "mono", problems, true)
		r.debug_symbols = _bool(item, "debug_symbols", problems, true)
		r.templates = _bool(item, "templates", problems, true)
		r.mono_templates = _bool(item, "mono_templates", problems, true)
		r.editor_size = _int(item, "editor_size", problems)
		r.mono_size = _int(item, "mono_size", problems)
		r.templates_size = _int(item, "templates_size", problems)
		r.url = _str(item, "url", problems, "")  # 2.2+
		out.append(r)
	if not problems.is_empty():
		return _bad("; ".join(problems), text)
	return GmResult.success(out)


## `which` → Resolution.
static func parse_which(text: String) -> GmResult:
	var root := _parse_json(text)
	if not root.ok:
		return root
	if not root.value is Dictionary:
		return _bad("se esperaba un objeto", text)
	var d: Dictionary = root.value
	var problems: Array[String] = []
	var r := Resolution.new()
	r.path = _str(d, "path", problems, null)
	r.version = _str(d, "version", problems, null)
	r.source = _str(d, "source", problems, "")
	if not problems.is_empty():
		return _bad("; ".join(problems), text)
	return GmResult.success(r)


## `plugins` → Array[ProjectPlugin], en el orden del CLI.
static func parse_plugins(text: String) -> GmResult:
	var root := _parse_json(text)
	if not root.ok:
		return root
	if not root.value is Dictionary:
		return _bad("se esperaba un objeto con 'plugins'", text)
	var problems: Array[String] = []
	var out: Array[ProjectPlugin] = []
	var items := _arr(root.value, "plugins", problems, true)
	for i in items.size():
		if not items[i] is Dictionary:
			problems.append("plugins[%d] no es un objeto" % i)
			continue
		var item: Dictionary = items[i]
		var p := ProjectPlugin.new()
		p.id = _str(item, "id", problems, null)
		p.name = _str(item, "name", problems, "")
		p.description = _str(item, "description", problems, "")
		p.author = _str(item, "author", problems, "")
		p.version = _str(item, "version", problems, "")
		p.script_path = _str(item, "script", problems, "")
		p.path = _str(item, "path", problems, "")
		p.enabled = _bool(item, "enabled", problems, false)
		p.missing = _bool(item, "missing", problems, false)
		p.problems = _str_list(item, "problems", problems)
		out.append(p)
	if not problems.is_empty():
		return _bad("; ".join(problems), text)
	return GmResult.success(out)


## `self-update --check` → UpdateInfo.
static func parse_update_check(text: String) -> GmResult:
	var root := _parse_json(text)
	if not root.ok:
		return root
	if not root.value is Dictionary:
		return _bad("se esperaba un objeto", text)
	var d: Dictionary = root.value
	var problems: Array[String] = []
	var u := UpdateInfo.new()
	u.current = _str(d, "current", problems, null)
	u.latest = _str(d, "latest", problems, null)
	u.update_available = _bool(d, "update_available", problems, false)
	u.can_update = _bool(d, "can_update", problems, false)
	u.reason = _str(d, "reason", problems, "")
	u.url = _str(d, "url", problems, "")
	u.dir = _str(d, "dir", problems, "")
	if not problems.is_empty():
		return _bad("; ".join(problems), text)
	return GmResult.success(u)


## Respuesta {"ok":true,…} de set, set-local, add, remove, launch/run --detach
## → el Dictionary entero.
static func parse_ok(text: String) -> GmResult:
	var root := _parse_json(text)
	if not root.ok:
		return root
	if not root.value is Dictionary or (root.value as Dictionary).get("ok") != true:
		return _bad("se esperaba {\"ok\":true,…}", text)
	return GmResult.success(root.value)


## Una línea de install / templates / symbols → CliEvent. Un evento `error`
## es un resultado válido (ok) con kind ERROR; solo una línea ilegible da error.
static func parse_event(line: String) -> GmResult:
	var root := _parse_json(line)
	if not root.ok:
		# {"error":{…}} suelto (por ejemplo, invalid_args antes de empezar).
		if root.error.code != CliError.BAD_OUTPUT:
			var err_ev := CliEvent.new()
			err_ev.kind = CliEvent.Kind.ERROR
			err_ev.error = root.error
			return GmResult.success(err_ev)
		return root
	if not root.value is Dictionary:
		return _bad("se esperaba un evento", line)
	var d: Dictionary = root.value
	var problems: Array[String] = []
	var ev := CliEvent.new()
	match _str(d, "event", problems, null):
		"step":
			ev.kind = CliEvent.Kind.STEP
			ev.message = _str(d, "message", problems, "")
		"warn":
			ev.kind = CliEvent.Kind.WARN
			ev.message = _str(d, "message", problems, "")
		"download":
			ev.kind = CliEvent.Kind.DOWNLOAD
			ev.file = _str(d, "file", problems, "")
			ev.done = _int(d, "done", problems)
			ev.total = _int(d, "total", problems)
		"done":
			ev.kind = CliEvent.Kind.DONE
			ev.data = d
		"error":
			ev.kind = CliEvent.Kind.ERROR
			ev.error = _error_from(d)
		var other:
			if problems.is_empty():
				problems.append("evento desconocido '%s'" % other)
	if not problems.is_empty():
		return _bad("; ".join(problems), line)
	return GmResult.success(ev)


## Resultado de `godot-manager version` → la versión del CLI ("2.1.0").
## La 1.x (bash) no tiene `version`: sale con error o imprime el uso; eso y
## cualquier versión < 2 dan el error `old_cli`.
static func parse_cli_version(job: CliJob) -> GmResult:
	if job.start_error != null:
		return GmResult.failure(job.start_error)
	var first := job.stdout.strip_edges().get_slice("\n", 0).strip_edges().trim_prefix("v")
	var looks_like_version := first.is_valid_float() or (first.get_slice(".", 0).is_valid_int() and first.contains("."))
	if job.exit_code == 0 and looks_like_version:
		var major := first.get_slice(".", 0).to_int()
		if major >= MIN_CLI_MAJOR:
			return GmResult.success(first)
		return GmResult.failure(CliError.make(OLD_CLI,
			TranslationServer.translate("Este godot-manager es la versión %s; la UI necesita la %d.x o más nueva.") % [first, MIN_CLI_MAJOR]))
	var output := (job.stdout + job.stderr).strip_edges()
	if output.length() > MAX_ORIGINAL:
		output = output.left(MAX_ORIGINAL) + "…"
	var msg := TranslationServer.translate("Este godot-manager no entiende 'version': parece una versión vieja (la 1.x, en bash). La UI necesita la %d.x o más nueva.") % MIN_CLI_MAJOR
	if job.cancelled:
		msg = TranslationServer.translate("Se canceló la prueba de godot-manager.")
	if not output.is_empty():
		msg += TranslationServer.translate("\nSalida (código %d):\n%s") % [job.exit_code, output]
	return GmResult.failure(CliError.make(OLD_CLI, msg))


## El error de un job que falló, para mostrarlo tal cual: el que no lo dejó
## arrancar; si no, el último {"error":…} o evento error de stdout; si no, el
## stderr (sin el prefijo "Error: "); si no, el código de salida.
## null si el job terminó bien o se canceló.
static func job_error(job: CliJob) -> CliError:
	if job.start_error != null:
		return job.start_error
	if job.cancelled or job.exit_code == 0:
		return null
	var lines := job.stdout.strip_edges().split("\n", false)
	if not lines.is_empty():
		var last := lines[lines.size() - 1]
		var ev := parse_event(last)
		if ev.ok and (ev.value as CliEvent).kind == CliEvent.Kind.ERROR:
			return (ev.value as CliEvent).error
		# list / which salen en varias líneas: probar con todo stdout.
		var whole := _parse_json(job.stdout)
		if not whole.ok and whole.error.code != CliError.BAD_OUTPUT:
			return whole.error
	var err := job.stderr.strip_edges()
	if not err.is_empty():
		return CliError.make(CliError.EXIT_CODE, err.trim_prefix("Error: ").trim_prefix("error: "))
	return CliError.make(CliError.EXIT_CODE, TranslationServer.translate("godot-manager terminó con código %d sin decir por qué.") % job.exit_code)


## "4.8.1-beta3" → [4, 8, 1]; lo que no sea número cuenta como 0.
static func version_numbers(tag: String) -> PackedInt32Array:
	var nums: PackedInt32Array = [0, 0, 0]
	var parts := tag.get_slice("-", 0).split(".")
	for i in mini(parts.size(), 3):
		nums[i] = parts[i].to_int() if parts[i].is_valid_int() else 0
	return nums


## Clave para ordenar tags de más vieja a más nueva:
## [mayor, menor, parche, etapa (dev<alpha<beta<rc<stable), número de etapa].
static func version_sort_key(tag: String) -> Array[int]:
	var nums := version_numbers(tag)
	var stage := STAGES["stable"] as int
	var stage_num := 0
	var suffix := tag.get_slice("-", 1) if tag.contains("-") else "stable"
	for s: String in STAGES:
		if suffix.begins_with(s):
			stage = STAGES[s]
			var rest := suffix.substr(s.length())
			stage_num = rest.to_int() if rest.is_valid_int() else 0
			break
	return [nums[0], nums[1], nums[2], stage, stage_num]


## true si `a` es una versión más nueva que `b`.
static func is_newer(a: String, b: String) -> bool:
	var ka := version_sort_key(a)
	var kb := version_sort_key(b)
	for i in ka.size():
		if ka[i] != kb[i]:
			return ka[i] > kb[i]
	return false


# --- Internos -----------------------------------------------------------------

## Parsea el texto entero. {"error":{…}} → failure con el CliError del CLI.
static func _parse_json(text: String) -> GmResult:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return GmResult.failure(CliError.make(CliError.BAD_OUTPUT, TranslationServer.translate("el CLI no devolvió nada")))
	var json := JSON.new()
	if json.parse(trimmed) != OK:
		var why := json.get_error_message()
		if why.length() > 80:
			why = why.left(80) + "…"
		return _bad("JSON inválido (%s, línea %d)" % [why, json.get_error_line()], text)
	var data: Variant = json.data
	if data is Dictionary and (data as Dictionary).has("error"):
		var err: Variant = (data as Dictionary)["error"]
		if err is Dictionary:
			return GmResult.failure(_error_from(err))
		return _bad("'error' no es un objeto", text)
	return GmResult.success(data)


static func _error_from(d: Dictionary) -> CliError:
	var extra := d.duplicate()
	extra.erase("code")
	extra.erase("message")
	extra.erase("event")
	var code: Variant = d.get("code", "")
	var message: Variant = d.get("message", "")
	return CliError.make(str(code), str(message), extra)


static func _bad(why: String, original: String) -> GmResult:
	var shown := original.strip_edges()
	if shown.length() > MAX_ORIGINAL:
		shown = shown.left(MAX_ORIGINAL) + "…"
	var msg := TranslationServer.translate("Salida inesperada del CLI: %s\n%s") % [why, shown]
	return GmResult.failure(CliError.make(CliError.BAD_OUTPUT, msg, {"original": original}))


## `fallback` null = campo obligatorio.
static func _str(d: Dictionary, key: String, problems: Array[String], fallback: Variant) -> String:
	if not d.has(key) or d[key] == null:
		if fallback == null:
			problems.append("falta '%s'" % key)
			return ""
		return fallback
	if not d[key] is String:
		problems.append("'%s' no es texto" % key)
		return ""
	return d[key]


static func _bool(d: Dictionary, key: String, problems: Array[String], fallback: bool) -> bool:
	if not d.has(key) or d[key] == null:
		return fallback
	if not d[key] is bool:
		problems.append("'%s' no es true/false" % key)
		return fallback
	return d[key]


## Números del JSON (llegan como float) a int; falta → 0.
static func _int(d: Dictionary, key: String, problems: Array[String]) -> int:
	if not d.has(key) or d[key] == null:
		return 0
	var v: Variant = d[key]
	if v is int:
		return v
	if v is float and is_equal_approx(v, roundf(v)):
		return int(v)
	problems.append("'%s' no es un entero" % key)
	return 0


static func _arr(d: Dictionary, key: String, problems: Array[String], required: bool) -> Array:
	if not d.has(key) or d[key] == null:
		if required:
			problems.append("falta '%s'" % key)
		return []
	if not d[key] is Array:
		problems.append("'%s' no es una lista" % key)
		return []
	return d[key]


static func _str_list(d: Dictionary, key: String, problems: Array[String]) -> PackedStringArray:
	var out: PackedStringArray = []
	for item: Variant in _arr(d, key, problems, false):
		if item is String:
			out.append(item)
		else:
			problems.append("'%s' tiene algo que no es texto" % key)
			break
	return out
