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


## Busca en el Asset Store plugins que anden con el Godot del proyecto (2.4+).
static func plugin_search(dir: String, query: String, page := 1) -> PackedStringArray:
	return _with_dir(dir, ["plugins", "search", query, "--page", str(page)])


## Instala un plugin y lo anota en plugins.json/plugins.lock (eventos).
## `source`: "store:pub/slug", "github:owner/repo", una URL, con @versión opcional.
static func plugin_add(dir: String, source: String, pin := false) -> PackedStringArray:
	var args := _with_dir(dir, ["plugins", "add", source])
	if pin:
		args.append("--pin")
	return args


## Instala lo que pide plugins.json en las versiones de plugins.lock (eventos).
static func plugin_install(dir: String) -> PackedStringArray:
	return _with_dir(dir, ["plugins", "install"])


## Versiones nuevas de los plugins de plugins.lock. Consulta las fuentes.
static func plugin_outdated(dir: String) -> PackedStringArray:
	return _with_dir(dir, ["plugins", "outdated"])


## Actualiza los no fijados (o los de `names`) a la más nueva que anda (eventos).
static func plugin_update(dir: String, names: PackedStringArray = []) -> PackedStringArray:
	var args := _with_dir(dir, ["plugins", "update"])
	args.append_array(names)
	return args


## Fija un plugin en la versión instalada (eventos).
static func plugin_pin(dir: String, name: String) -> PackedStringArray:
	return _with_dir(dir, ["plugins", "pin", name])


static func plugin_unpin(dir: String, name: String) -> PackedStringArray:
	return _with_dir(dir, ["plugins", "unpin", name])


## Suma al proyecto los plugins de un preset y los instala (eventos).
static func plugin_apply(dir: String, preset: String) -> PackedStringArray:
	return _with_dir(dir, ["plugins", "apply", preset])


## Los presets de plugins (2.4+).
static func presets() -> PackedStringArray:
	return ["--json", "presets"]


## Guarda los plugins.json de `dir` como preset (reemplaza uno con ese nombre).
## `pin`: cada plugin fijado en la versión que tiene instalada.
static func preset_save(dir: String, name: String, pin := false) -> PackedStringArray:
	var args := _with_dir(dir, ["presets", "save", name, "--force"])
	if pin:
		args.append("--pin")
	return args


static func preset_remove(name: String) -> PackedStringArray:
	return ["--json", "presets", "remove", name]


## Crea un proyecto de Godot 4 vacío en `dir` (eventos). `version` "" = sin
## .godot-version (sigue a la default); `renderer`: forward_plus, mobile o
## gl_compatibility; `preset` "" = sin plugins.
static func new_project(dir: String, name: String, version := "", renderer := "forward_plus", preset := "") -> PackedStringArray:
	var args: PackedStringArray = ["--json", "new", dir, "--name", name, "--renderer", renderer]
	if not version.is_empty():
		args.append_array(["--version", version])
	if not preset.is_empty():
		args.append_array(["--preset", preset])
	return args


## Las versiones instaladas que tienen una más nueva de su serie (2.4+).
## Consulta GitHub.
static func outdated() -> PackedStringArray:
	return ["--json", "outdated"]


## Instala la más nueva de la serie de `version` con lo mismo que tenía
## (eventos, como install); si era la default, la nueva pasa a serlo.
static func upgrade(version: String) -> PackedStringArray:
	return ["--json", "upgrade", version]


## Versiones oficiales que no usa la default ni ningún proyecto (2.4+). El CLI
## suma la lista del Project Manager de Godot; `projects` es la de la UI.
## `dry_run`: solo las lista; si no, las borra (la UI confirma antes).
static func prune(projects: PackedStringArray, dry_run: bool) -> PackedStringArray:
	var args: PackedStringArray = ["--json", "prune", "--dry-run" if dry_run else "--yes"]
	args.append_array(projects)
	return args


## Si godot-manager está en el PATH (2.4+).
static func path_status() -> PackedStringArray:
	return ["--json", "path"]


## Las carpetas que usa godot-manager, con la que usaría sin GODOT_DIR (2.5+).
static func dirs() -> PackedStringArray:
	return ["--json", "dirs"]


## Lo agrega al PATH (o lo quita): en Windows el del usuario, en el resto
## symlinks en ~/.local/bin.
static func path_change(add: bool) -> PackedStringArray:
	return ["--json", "path", "add" if add else "remove"]


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
