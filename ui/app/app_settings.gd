class_name AppSettings
extends RefCounted
## Ajustes de la UI en `user://settings.cfg` (ConfigFile: no ejecuta código al
## cargar). El GITHUB_TOKEN queda en texto plano: Godot no tiene acceso al
## llavero del sistema.

const PATH := "user://settings.cfg"
const DEFAULT_BINARY := "godot-manager"

enum BinaryMode { SEARCH_PATH, FIXED }

var binary_mode := BinaryMode.SEARCH_PATH
## Ruta del binario cuando binary_mode es FIXED.
var binary_path := ""
var github_token := ""
## Vacío = el default del CLI.
var godot_dir := ""


## Lo que GmCli tiene que ejecutar: el nombre (se busca en PATH) o la ruta.
func binary() -> String:
	if binary_mode == BinaryMode.FIXED and not binary_path.strip_edges().is_empty():
		return binary_path.strip_edges()
	return DEFAULT_BINARY


## Entorno para el CLI (vacío = no tocar la variable).
func cli_env() -> Dictionary:
	return {"GITHUB_TOKEN": github_token.strip_edges(), "GODOT_DIR": godot_dir.strip_edges()}


## Pasa los ajustes a GmCli (o a otro nodo con `binary` y `env`).
func apply_to(cli: Node) -> void:
	cli.set("binary", binary())
	cli.set("env", cli_env())


func save(path := PATH) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("cli", "binary_mode", "fixed" if binary_mode == BinaryMode.FIXED else "path")
	cfg.set_value("cli", "binary_path", binary_path)
	cfg.set_value("cli", "github_token", github_token)
	cfg.set_value("cli", "godot_dir", godot_dir)
	return cfg.save(path)


## Carga los ajustes; si el archivo no existe o está roto, los de fábrica.
static func load_from(path := PATH) -> AppSettings:
	var s := AppSettings.new()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return s
	s.binary_mode = BinaryMode.FIXED if str(cfg.get_value("cli", "binary_mode", "path")) == "fixed" else BinaryMode.SEARCH_PATH
	s.binary_path = str(cfg.get_value("cli", "binary_path", ""))
	s.github_token = str(cfg.get_value("cli", "github_token", ""))
	s.godot_dir = str(cfg.get_value("cli", "godot_dir", ""))
	return s


func duplicate_settings() -> AppSettings:
	var s := AppSettings.new()
	s.binary_mode = binary_mode
	s.binary_path = binary_path
	s.github_token = github_token
	s.godot_dir = godot_dir
	return s
