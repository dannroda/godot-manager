class_name ProjectStatus
extends RefCounted
## Con qué versión se abriría un proyecto, según `--dir <proyecto> which`, y
## cómo se muestra en su fila. La UI no lee el .godot-version: lo resuelve el CLI.

enum State { PENDING, PINNED, DEFAULT, NOT_INSTALLED, ERROR }

var state := State.PENDING
var resolution: Resolution
var error: CliError


## Del job de `which` ya terminado.
static func from_job(job: CliJob) -> ProjectStatus:
	var s := ProjectStatus.new()
	var r := GmParse.parse_which(job.stdout) if job.start_error == null else null
	if r != null and r.ok and job.succeeded():
		s.resolution = r.value
		s.state = State.DEFAULT if s.resolution.is_from_default() else State.PINNED
		return s
	s.error = r.error if r != null and not r.ok else GmParse.job_error(job)
	if s.error == null:
		s.error = CliError.make(CliError.EXIT_CODE, "which terminó con código %d" % job.exit_code)
	s.state = State.NOT_INSTALLED if s.error.code == "not_installed" else State.ERROR
	return s


static func pending() -> ProjectStatus:
	return ProjectStatus.new()


## La versión que falta instalar (solo en NOT_INSTALLED), sacada del campo
## `version` del error del CLI, nunca del texto.
func missing_version() -> String:
	if state != State.NOT_INSTALLED or error == null:
		return ""
	return str(error.extra.get("version", ""))


func is_error() -> bool:
	return state == State.NOT_INSTALLED or state == State.ERROR


## Lo que dice la fila: "4.8-beta3 · fijada", "4.7.2-stable · default"…
func text() -> String:
	match state:
		State.PINNED:
			return "%s · fijada" % resolution.version
		State.DEFAULT:
			return "%s · default" % resolution.version
		State.NOT_INSTALLED:
			var v := missing_version()
			return ("%s no instalada" % v) if not v.is_empty() else "Versión no instalada"
		State.ERROR:
			if error.code == "no_default":
				return "Sin versión por defecto"
			return "Error al resolver la versión"
	return "…"


## El detalle: de dónde sale la versión, o el mensaje del CLI tal cual.
func tooltip() -> String:
	match state:
		State.PINNED:
			return "Fijada por %s\n%s" % [resolution.source, resolution.path]
		State.DEFAULT:
			return "El proyecto no tiene .godot-version: usa la versión por defecto.\n%s" % resolution.path
		State.NOT_INSTALLED, State.ERROR:
			return error.message
	return "Buscando la versión…"
