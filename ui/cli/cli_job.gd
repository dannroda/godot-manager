class_name CliJob
extends RefCounted
## Una llamada a godot-manager. La crea y la bombea GmCli; quien la pidió se
## conecta a sus señales o hace `await job.finished`.

## Una línea completa de stdout o stderr (sin el salto de línea).
signal line_received(stream: Stream, text: String)
## Terminó (bien, mal o cancelada); `exit_code`, `stdout`, `stderr` ya están.
signal finished(job: CliJob)

enum Kind { READ, WRITE }
enum State { QUEUED, RUNNING, DONE }
enum Stream { STDOUT, STDERR }

const READ_CHUNK := 65536

var args: PackedStringArray
var kind := Kind.READ
## Si falla, main muestra el aviso de error. La pantalla que muestre el error
## por su cuenta (por ejemplo, en la lista) lo pone en false.
var notify_on_error := true
## Lectura de fondo (por ejemplo, un `which` por proyecto): no va al historial
## y Salida solo la muestra si falla. La crea GmCli.read_background.
var background := false
## Binario a usar en vez del de GmCli (vacío: el de GmCli).
var binary_override := ""
## Ruta con la que se lanzó (la pone GmCli).
var binary := ""
var state := State.QUEUED
var pid := -1
## -1 mientras corre, si no arrancó o si se canceló.
var exit_code := -1
var stdout := ""
var stderr := ""
var cancelled := false
## Error de la UI al lanzar (sin binario, no arrancó); null si arrancó.
var start_error: CliError
var queued_msec := 0
var started_msec := 0
var ended_msec := 0

var _stdio: FileAccess
var _stderr_pipe: FileAccess
var _out_buf := PackedByteArray()
var _err_buf := PackedByteArray()


func _init(p_args: PackedStringArray, p_kind: Kind) -> void:
	args = p_args
	kind = p_kind
	queued_msec = Time.get_ticks_msec()


func is_done() -> bool:
	return state == State.DONE


## Terminó con código 0 y sin cancelar.
func succeeded() -> bool:
	return state == State.DONE and exit_code == 0 and not cancelled


## El comando como se vería en una terminal (solo para mostrar).
func command_line() -> String:
	return format_command(args, binary.get_file() if not binary.is_empty() else "godot-manager")


## `args` como se verían en una terminal, con comillas donde hace falta: en
## Windows dobles (para pegarlo en cmd o PowerShell), si no simples de sh.
static func format_command(p_args: PackedStringArray, program := "godot-manager",
		windows := OS.get_name() == "Windows") -> String:
	var parts: PackedStringArray = [program if _plain(program) else _quote(program, windows)]
	for a in p_args:
		parts.append(a if _plain(a) else _quote(a, windows))
	return " ".join(parts)


static func _quote(a: String, windows: bool) -> String:
	if windows:
		return "\"%s\"" % a.replace("\"", "\\\"")
	return "'%s'" % a.replace("'", "'\\''")


func duration_msec() -> int:
	if started_msec == 0:
		return 0
	return (ended_msec if ended_msec > 0 else Time.get_ticks_msec()) - started_msec


# --- Uso de GmCli -------------------------------------------------------------

func _start(path: String) -> void:
	state = State.RUNNING
	started_msec = Time.get_ticks_msec()
	var info := OS.execute_with_pipe(path, args, false)
	if info.is_empty():
		start_error = CliError.make(CliError.START_FAILED, tr("No se pudo ejecutar %s") % path)
		_finish()
		return
	pid = info["pid"]
	_stdio = info["stdio"]
	_stderr_pipe = info["stderr"]


## Lee lo disponible sin bloquear; devuelve true cuando el job terminó.
func _pump() -> bool:
	if state != State.RUNNING:
		return state == State.DONE
	var running := OS.is_process_running(pid)
	_out_buf = _drain(_stdio, _out_buf, Stream.STDOUT)
	_err_buf = _drain(_stderr_pipe, _err_buf, Stream.STDERR)
	if running:
		return false
	# Terminó: lo que quede en los pipes ya está escrito, leerlo todo.
	_out_buf = _drain(_stdio, _out_buf, Stream.STDOUT)
	_err_buf = _drain(_stderr_pipe, _err_buf, Stream.STDERR)
	if not _out_buf.is_empty():
		_emit_line(_out_buf, Stream.STDOUT)
		_out_buf = PackedByteArray()
	if not _err_buf.is_empty():
		_emit_line(_err_buf, Stream.STDERR)
		_err_buf = PackedByteArray()
	if not cancelled:
		exit_code = OS.get_process_exit_code(pid)
	_finish()
	return true


func _cancel() -> void:
	if state == State.DONE:
		return
	cancelled = true
	if state == State.RUNNING and pid > 0:
		# OS.kill también recoge el proceso: después de esto el pid ya no es
		# consultable, así que se lee lo que quedó y se cierra acá mismo.
		OS.kill(pid)
		_out_buf = _drain(_stdio, _out_buf, Stream.STDOUT)
		_err_buf = _drain(_stderr_pipe, _err_buf, Stream.STDERR)
	_finish()


func _finish() -> void:
	state = State.DONE
	ended_msec = Time.get_ticks_msec()
	_stdio = null
	_stderr_pipe = null
	finished.emit(self)


## Lee lo disponible del pipe, emite las líneas completas y devuelve lo que
## quedó sin salto de línea (los Packed*Array se pasan por valor).
func _drain(pipe: FileAccess, buf: PackedByteArray, stream: Stream) -> PackedByteArray:
	if pipe == null:
		return buf
	while true:
		var chunk := pipe.get_buffer(READ_CHUNK)
		if chunk.is_empty():
			break
		buf.append_array(chunk)
		if chunk.size() < READ_CHUNK:
			break
	var start := 0
	var nl := buf.find(10, start)
	while nl != -1:
		_emit_line(buf.slice(start, nl), stream)
		start = nl + 1
		nl = buf.find(10, start)
	return buf.slice(start) if start > 0 else buf


func _emit_line(bytes: PackedByteArray, stream: Stream) -> void:
	var text := bytes.get_string_from_utf8().trim_suffix("\r")
	if stream == Stream.STDOUT:
		stdout += text + "\n"
	else:
		stderr += text + "\n"
	line_received.emit(stream, text)


static func _plain(a: String) -> bool:
	if a.is_empty():
		return false
	for c in a:
		if not (c.is_valid_identifier() or c in "-_.,/=:+@0123456789"):
			return false
	return true
