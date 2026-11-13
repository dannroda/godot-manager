extends Node
## Autoload `GmCli`: toda llamada a godot-manager pasa por acá, sin bloquear.
##
##   var job := GmCli.read(GmCommands.list())
##   await job.finished
##   var r := GmParse.parse_list(job.stdout)
##
## Las lecturas (`read`) arrancan enseguida y pueden correr a la vez. Las
## escrituras (`write`: install, set, remove, set-local, add…) van en una cola
## y corren de a una. Cada job queda en `history` para el panel de salida.

signal job_started(job: CliJob)
signal job_finished(job: CliJob)
## Terminó una escritura (bien, mal o cancelada): lo instalado puede haber
## cambiado. Las pantallas que muestran versiones se refrescan con esto.
signal versions_changed
## Resultado de `check()`: si el binario es un godot-manager 2.x usable.
signal availability_changed(ok: bool, message: String)

const HISTORY_LIMIT := 200
## Variables que se pasan al CLI por entorno (las define Ajustes).
const ENV_KEYS: PackedStringArray = ["GITHUB_TOKEN", "GODOT_DIR"]

## Ruta del binario, o un nombre que se busca en PATH.
var binary := "godot-manager"
## Entorno para el CLI: valor vacío = dejar el que tenía el proceso al abrir.
var env := {}
var history: Array[CliJob] = []
## Lo deja `check()`. Las pantallas no llaman al CLI mientras sea false.
var available := false
var cli_version := ""
var availability_message := ""

var _running: Array[CliJob] = []
var _write_queue: Array[CliJob] = []
var _write_running: CliJob
## Valor que tenía cada variable antes de que GmCli la pisara (null: no existía).
var _saved_env := {}


func _ready() -> void:
	set_process(false)


## Lanza una lectura ya. `binary_override` corre otro binario solo esta vez
## (lo usa el botón Probar de Ajustes).
func read(args: PackedStringArray, binary_override := "") -> CliJob:
	var job := CliJob.new(args, CliJob.Kind.READ)
	job.binary_override = binary_override
	_remember(job)
	_launch(job)
	return job


## Lectura de fondo, de las que se lanzan muchas juntas (un `which` por
## proyecto): sin aviso de error (lo muestra quien la pidió), fuera del
## historial, y en Salida solo si falla.
func read_background(args: PackedStringArray) -> CliJob:
	var job := CliJob.new(args, CliJob.Kind.READ)
	job.background = true
	job.notify_on_error = false
	_launch(job)
	return job


## Encola una escritura; arranca cuando termina la anterior.
func write(args: PackedStringArray) -> CliJob:
	var job := CliJob.new(args, CliJob.Kind.WRITE)
	_remember(job)
	_write_queue.append(job)
	_next_write()
	return job


## Mata el proceso (o lo saca de la cola si no arrancó).
func cancel(job: CliJob) -> void:
	if job.is_done():
		return
	if job.state == CliJob.State.QUEUED:
		_write_queue.erase(job)
		job._cancel()
		job_finished.emit(job)
		return
	job._cancel()
	_running.erase(job)
	_on_done(job)


## Corre `version` con un binario (sin tocar `binary` ni `available`).
func probe(binary_to_test: String) -> GmResult:
	var job := read(GmCommands.cli_version(), binary_to_test)
	if not job.is_done():
		await job.finished
	return GmParse.parse_cli_version(job)


## Corre `version` con el binario actual y actualiza `available`.
func check() -> GmResult:
	var r: GmResult = await probe(binary)
	available = r.ok
	cli_version = r.value if r.ok else ""
	availability_message = "" if r.ok else r.error.message
	availability_changed.emit(available, availability_message)
	return r


func is_busy() -> bool:
	return not _running.is_empty() or not _write_queue.is_empty()


## Ruta absoluta del binario: `bin_name` si es una ruta, o la primera
## coincidencia en PATH. Vacío si no se encuentra.
static func resolve_binary(bin_name: String) -> String:
	if bin_name.is_empty():
		return ""
	if bin_name.is_absolute_path() or bin_name.contains("/") or bin_name.contains("\\"):
		return bin_name if FileAccess.file_exists(bin_name) else ""
	var windows := OS.get_name() == "Windows"
	var candidates: PackedStringArray = [bin_name]
	if windows and not bin_name.to_lower().ends_with(".exe"):
		candidates.insert(0, bin_name + ".exe")
	for dir in path_dirs(OS.get_environment("PATH"), windows):
		for c in candidates:
			var full := dir.path_join(c)
			if FileAccess.file_exists(full):
				return full
	return ""


## Las carpetas de un PATH: `;` en Windows (donde una entrada puede venir
## entre comillas, `"C:\Program Files\x"`), `:` en el resto.
static func path_dirs(path_env: String, windows: bool) -> PackedStringArray:
	var out := PackedStringArray()
	for dir in path_env.split(";" if windows else ":", false):
		if windows:
			dir = dir.strip_edges().trim_prefix("\"").trim_suffix("\"")
		if not dir.is_empty():
			out.append(dir)
	return out


func _launch(job: CliJob) -> void:
	var wanted := job.binary_override if not job.binary_override.is_empty() else binary
	var path := resolve_binary(wanted)
	job.binary = path if not path.is_empty() else wanted
	if path.is_empty():
		var where := "en el PATH" if wanted.get_file() == wanted else "en %s" % wanted
		job.start_error = CliError.make(CliError.NO_BINARY,
			"No se encontró godot-manager %s. Revisá el binario en Ajustes." % where)
		job.state = CliJob.State.RUNNING
		job_started.emit(job)
		job._finish()
		_on_done(job)
		return
	_apply_env()
	job._start(path)
	job_started.emit(job)
	if job.is_done():
		_on_done(job)
		return
	_running.append(job)
	set_process(true)


func _process(_delta: float) -> void:
	for job in _running.duplicate():
		if job._pump():
			_running.erase(job)
			_on_done(job)
	if _running.is_empty():
		set_process(false)


func _on_done(job: CliJob) -> void:
	job_finished.emit(job)
	if job.kind == CliJob.Kind.WRITE:
		versions_changed.emit()
	if job == _write_running:
		_write_running = null
		_next_write()


func _next_write() -> void:
	if _write_running != null or _write_queue.is_empty():
		return
	_write_running = _write_queue.pop_front()
	_launch(_write_running)


## Pone en el entorno los valores de `env` y, si uno se vació, restaura el que
## había antes de que GmCli lo cambiara. Lo que no tocó, no lo toca.
func _apply_env() -> void:
	for key in ENV_KEYS:
		var value := str(env.get(key, ""))
		if not value.is_empty():
			if not _saved_env.has(key):
				var previous: Variant = null
				if OS.has_environment(key):
					previous = OS.get_environment(key)
				_saved_env[key] = previous
			OS.set_environment(key, value)
		elif _saved_env.has(key):
			if _saved_env[key] == null:
				OS.unset_environment(key)
			else:
				OS.set_environment(key, _saved_env[key])
			_saved_env.erase(key)


func _remember(job: CliJob) -> void:
	history.append(job)
	if history.size() > HISTORY_LIMIT:
		history.pop_front()
