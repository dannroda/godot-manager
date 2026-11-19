extends SceneTree
## Entrada para correr la librería sin editor:
##   godot --headless --path <carpeta de pluginkit> --script res://cli.gd -- <operación> \
##     --project <dir> --out <archivo.json> [--godot 4.5.1] [--temp <dir>] [--force] [args...]
## Operaciones: search <texto> [página], add <fuente[@versión]> [--name n] [--pin] [--prerelease],
## install, outdated, update [nombres...], pin <nombre> [versión], unpin <nombre>,
## remove <nombre>, status, apply <preset.json>, preset-add <preset.json> <fuente[@versión]>...
## El progreso sale por stdout, una línea por aviso: `@pk {"progress": ..., ...}`. El resultado
## (lo que devuelve la operación, con `error` si falló) va a --out como JSON. Sale con 0 o 1.

const Kit := preload("kit.gd")
const Http := preload("http.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var options := {"project": "", "out": "", "godot": "", "temp": "", "name": ""}
	var flags := {"force": false, "pin": false, "prerelease": false}
	var rest := []
	while not args.is_empty():
		var arg: String = args.pop_front()
		if arg.begins_with("--") and options.has(arg.substr(2)) and not args.is_empty():
			options[arg.substr(2)] = args.pop_front()
		elif arg.begins_with("--") and flags.has(arg.substr(2)):
			flags[arg.substr(2)] = true
		else:
			rest.append(arg)
	var result := {}
	if rest.is_empty() or options.project.is_empty():
		result = {"error": "usage", "details": {}}
	else:
		var http := Http.new(root)
		http.user_agent = "godot-plugin-kit/%s (Godot %s)" % [Kit.VERSION, Engine.get_version_info().string]
		var temp: String = options.temp if not options.temp.is_empty() else OS.get_cache_dir().path_join("godot-plugin-kit")
		var kit := Kit.new(options.project.replace("\\", "/"), http, temp.replace("\\", "/"))
		kit.godot = options.godot
		kit.force = flags.force
		kit.progress.connect(func(what: String, data: Dictionary) -> void:
			data["progress"] = what
			print("@pk ", JSON.stringify(data)))
		result = await _call(kit, rest, options, flags)
	var text := JSON.stringify(result)
	if options.out.is_empty():
		print(text)
	else:
		var file := FileAccess.open(options.out, FileAccess.WRITE)
		if file:
			file.store_string(text)
			file.close()
	quit(1 if result.has("error") else 0)


func _call(kit: RefCounted, rest: Array, options: Dictionary, flags: Dictionary) -> Dictionary:
	var op: String = rest.pop_front()
	match op:
		"search":
			if rest.is_empty():
				return _usage()
			return await kit.search(rest[0], int(rest[1]) if rest.size() > 1 else 1)
		"add":
			if rest.size() != 1:
				return _usage()
			return await kit.add(rest[0], options.name, flags.pin, flags.prerelease)
		"install":
			return await kit.install()
		"outdated":
			return await kit.outdated()
		"update":
			return await kit.update(PackedStringArray(rest))
		"pin":
			if rest.is_empty() or rest.size() > 2:
				return _usage()
			return await kit.pin(rest[0], rest[1] if rest.size() > 1 else "")
		"unpin":
			return kit.unpin(rest[0]) if rest.size() == 1 else _usage()
		"remove":
			return kit.remove(rest[0]) if rest.size() == 1 else _usage()
		"status":
			return kit.status()
		"apply":
			if rest.size() != 1:
				return _usage()
			return await kit.apply(rest[0])
		"preset-add":
			if rest.size() < 2:
				return _usage()
			return kit.preset_add(rest[0], PackedStringArray(rest.slice(1)), flags.prerelease)
		"version":
			return {"version": Kit.VERSION}
	return _usage()


func _usage() -> Dictionary:
	return {"error": "usage", "details": {}}
