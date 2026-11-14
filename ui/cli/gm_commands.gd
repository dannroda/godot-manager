class_name GmCommands
extends RefCounted
## Argumentos de cada comando de godot-manager. Es el único lugar donde se
## arman: la UI nunca concatena strings ni pasa por un shell, así las rutas con
## espacios o comillas llegan tal cual. Todos empiezan con `--json`; `--dir`
## va siempre antes del comando (es global en el CLI).

## Plataformas que acepta --platforms.
const PLATFORMS: PackedStringArray = ["android", "ios", "linux", "macos", "visionos", "web", "windows"]


static func list() -> PackedStringArray:
	return ["--json", "list"]


## `filter`: "", "stable", "dev" o "latest".
static func list_remote(filter := "") -> PackedStringArray:
	var args: PackedStringArray = ["--json", "list-remote"]
	if not filter.is_empty():
		args.append(filter)
	return args


## Qué versión usaría `godot` en `dir` (vacío: el directorio actual).
static func which(dir := "") -> PackedStringArray:
	return _with_dir(dir, ["which"])


## Instala una versión oficial. `platforms` vacío con `templates` = todas.
static func install(version: String, mono := false, debug_symbols := false,
		with_templates := false, platforms: PackedStringArray = [], yes := false) -> PackedStringArray:
	var args: PackedStringArray = ["--json", "install", version]
	if mono:
		args.append("--mono")
	if debug_symbols:
		args.append("--debugsymbols")
	if with_templates:
		args.append("--templates")
	if not platforms.is_empty():
		args.append("--platforms=" + ",".join(platforms))
	if yes:
		args.append("--yes")
	return args


## Export templates de una versión instalada. `debug_symbols_only`: solo los
## símbolos de los templates ya instalados.
static func templates(version: String, mono := false, platforms: PackedStringArray = [],
		debug_symbols := false, debug_symbols_only := false, yes := false) -> PackedStringArray:
	var args: PackedStringArray = ["--json", "templates", version]
	if mono:
		args.append("--mono")
	if not platforms.is_empty():
		args.append("--platforms=" + ",".join(platforms))
	if debug_symbols:
		args.append("--debugsymbols")
	if debug_symbols_only:
		args.append("--debugsymbolsonly")
	if yes:
		args.append("--yes")
	return args


## Símbolos de debug del editor de una versión instalada.
static func symbols(version: String) -> PackedStringArray:
	return ["--json", "symbols", version]


static func set_default(version: String) -> PackedStringArray:
	return ["--json", "set", version]


## Fija la versión del proyecto en `dir` (escribe su .godot-version).
static func set_local(dir: String, version: String) -> PackedStringArray:
	return _with_dir(dir, ["set-local", version])


## Quita el .godot-version de `dir`.
static func unset_local(dir: String) -> PackedStringArray:
	return _with_dir(dir, ["set-local", "--unset"])


## La UI confirma antes, así que siempre va --yes; sin `remove_templates` los
## export templates se conservan.
static func remove(version: String, remove_templates := false) -> PackedStringArray:
	var args: PackedStringArray = ["--json", "remove", version, "--yes"]
	if remove_templates:
		args.append("--templates")
	return args


## Agrega un build propio.
static func add(name: String, path: String, symlink := false, force := false) -> PackedStringArray:
	var args: PackedStringArray = ["--json", "add", name, path]
	if symlink:
		args.append("--symlink")
	# 2.2+: reemplaza una versión con ese nombre (sin esto da already_installed).
	if force:
		args.append("--force")
	return args


## Abre una versión puntual, aparte (--detach), con `extra` para el editor.
static func launch(version: String, extra: PackedStringArray = [], dir := "") -> PackedStringArray:
	var args := _with_dir(dir, ["launch", "--detach", version])
	args.append_array(extra)
	return args


## Abre el proyecto de `dir` en el editor con la versión que le corresponde.
static func open_project(dir: String) -> PackedStringArray:
	return _with_dir(dir, ["run", "--detach", "-e"])


## Corre el proyecto de `dir` (sin editor) con la versión que le corresponde.
static func run_project(dir: String) -> PackedStringArray:
	return _with_dir(dir, ["run", "--detach"])


## Los plugins del proyecto de `dir` (2.3+).
static func plugins(dir: String) -> PackedStringArray:
	return _with_dir(dir, ["plugins"])


## Activa o desactiva un plugin en el project.godot de `dir`.
static func plugin_enable(dir: String, id: String, enable: bool) -> PackedStringArray:
	return _with_dir(dir, ["plugins", "enable" if enable else "disable", id])


## Desactiva un plugin y borra su carpeta. La UI confirma antes: va --yes.
static func plugin_remove(dir: String, id: String) -> PackedStringArray:
	return _with_dir(dir, ["plugins", "remove", id, "--yes"])


## Si hay una versión nueva de godot-manager (2.3+); un objeto, sin eventos.
static func self_update_check() -> PackedStringArray:
	return ["--json", "self-update", "--check"]


## Actualiza godot-manager (eventos, como install). La UI confirma antes.
static func self_update() -> PackedStringArray:
	return ["--json", "self-update", "--yes"]


## `godot-manager version` (sin --json: imprime solo el número).
static func cli_version() -> PackedStringArray:
	return ["version"]


static func _with_dir(dir: String, rest: PackedStringArray) -> PackedStringArray:
	var args: PackedStringArray = ["--json"]
	if not dir.is_empty():
		args.append_array(["--dir", dir])
	args.append_array(rest)
	return args
