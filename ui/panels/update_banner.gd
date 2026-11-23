extends PanelContainer
## Franja de "hay una versión nueva de godot-manager". `check_if_due` pregunta
## al CLI (`self-update --check`) como mucho una vez por día; si hay una
## nueva, se muestra con Actualizar (si se puede), Novedades y cerrar.
## Actualizar emite `update_requested` (main lo corre en el panel de
## progreso) y, al terminar bien, ofrece reiniciar la interfaz.

signal update_requested(args: PackedStringArray, title: String)

const CHECK_EVERY := 24 * 60 * 60

var info: UpdateInfo
## Ya se actualizó: lo que queda es reiniciar.
var updated := false
## El ejecutable de la interfaz, leído al arrancar. Después de actualizar,
## OS.get_executable_path() ya no sirve en Linux: /proc/self/exe apunta al
## binario viejo, que self-update borró ("….old (deleted)").
var executable_path := OS.get_executable_path()

@onready var _text: Label = %UpdateText
@onready var _update: Button = %UpdateNow
@onready var _notes: Button = %UpdateNotes
@onready var _restart: Button = %UpdateRestart


func _ready() -> void:
	visible = false
	_update.pressed.connect(func() -> void:
		update_requested.emit(GmCommands.self_update(), tr("Actualizar godot-manager a %s") % info.latest))
	_notes.pressed.connect(func() -> void:
		if info != null and not info.url.is_empty():
			OS.shell_open(info.url))
	_restart.pressed.connect(restart)
	%UpdateClose.pressed.connect(func() -> void: visible = false)


## Pregunta si toca (activado en Ajustes y pasó un día desde la última vez
## que salió bien). Devuelve si preguntó; la hora se guarda en `settings` solo
## si la respuesta llegó, así un chequeo sin red se reintenta al abrir otra vez.
func check_if_due(settings: AppSettings, now := int(Time.get_unix_time_from_system())) -> bool:
	if not settings.check_updates or not GmCli.available:
		return false
	if settings.last_update_check > 0 and now - settings.last_update_check < CHECK_EVERY:
		return false
	_check_and_stamp(settings, now)
	return true


func _check_and_stamp(settings: AppSettings, now: int) -> void:
	var r := await check()
	if r.ok:
		settings.last_update_check = now
		settings.save()


## Pregunta ya y, si hay una nueva, muestra la franja. Devuelve el resultado
## (un UpdateInfo, o el error): la franja no muestra errores, porque al abrir
## nadie lo pidió; quien pregunta a mano (Ajustes) los muestra él.
func check() -> GmResult:
	var job := GmCli.read_background(GmCommands.self_update_check())
	job.notify_on_error = false
	await job.finished
	if not job.succeeded():
		return GmResult.failure(GmParse.job_error(job))
	var r := GmParse.parse_update_check(job.stdout)
	if r.ok:
		show_info(r.value)
	return r


func show_info(u: UpdateInfo) -> void:
	info = u
	updated = false
	if not u.update_available:
		visible = false
		return
	if u.can_update:
		_text.text = tr("Hay una versión nueva de godot-manager: %s (tenés %s).") % [u.latest, u.current]
	else:
		_text.text = tr("Hay una versión nueva de godot-manager: %s (tenés %s). No se puede actualizar sola: %s.") % [
			u.latest, u.current, u.reason]
	_update.visible = u.can_update
	_notes.visible = not u.url.is_empty()
	_restart.visible = false
	visible = true


## Lo llama main cuando terminó el job de Actualizar.
func on_update_finished(job: CliJob) -> void:
	if not job.succeeded():
		return  # El error ya lo muestra el panel de progreso.
	updated = true
	_update.visible = false
	_notes.visible = false
	var editor := OS.has_feature("editor")
	_restart.visible = not editor
	_text.text = tr("godot-manager se actualizó a %s. Reiniciá la interfaz para usar la versión nueva.") % info.latest
	visible = true


## Abre la interfaz otra vez (el ejecutable ya es el nuevo) y cierra esta.
## Si no se pudo abrir, no cierra: avisa que hay que abrirla a mano.
func restart() -> void:
	if launch(executable_path, OS.get_cmdline_args()) == -1:
		_text.text = tr("No se pudo abrir la interfaz nueva (%s). Cerrala y abrila a mano.") % executable_path
		return
	get_tree().quit()


## Lanza el ejecutable; devuelve el PID o -1. Los tests lo reemplazan.
var launch := func(path: String, args: PackedStringArray) -> int:
	if not FileAccess.file_exists(path):
		return -1
	return OS.create_process(path, args)
