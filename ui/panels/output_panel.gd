extends PanelContainer
## Panel "Salida" (como el Output del editor): cada comando que corrió la UI
## con su stdout, stderr y código. Plegable; Copiar y Limpiar.

## Salidas más largas que esto se recortan en el panel (list-remote ~100 kB).
const MAX_STREAM_CHARS := 4000
const COLOR_CMD := "#70bafa"
const COLOR_ERR := "#ff8a80"
const COLOR_OK := "#8fd18f"
const COLOR_DIM := "#8b919b"

@onready var _toggle: Button = %Toggle
@onready var _log: RichTextLabel = %Log
@onready var _body: Control = %Body

## Jobs que se ven (Limpiar vacía esta lista, no el historial de GmCli).
var _jobs: Array[CliJob] = []
var _render_queued := false


func _ready() -> void:
	_toggle.toggled.connect(_set_expanded)
	%Copy.pressed.connect(func() -> void: DisplayServer.clipboard_set(plain_text()))
	%Clear.pressed.connect(clear)
	GmCli.job_started.connect(_on_job)
	GmCli.job_finished.connect(_on_job)
	_set_expanded(_toggle.button_pressed)
	_update_title()


func expand() -> void:
	_toggle.button_pressed = true


func clear() -> void:
	_jobs.clear()
	_queue_render()


## Todo el panel en texto plano (lo que copia Copiar).
func plain_text() -> String:
	var parts: PackedStringArray = []
	for job in _jobs:
		parts.append(_job_text(job, false))
	return "\n".join(parts)


func _set_expanded(on: bool) -> void:
	_body.visible = on
	size_flags_vertical = Control.SIZE_FILL


func _on_job(job: CliJob) -> void:
	# Las de fondo (un which por proyecto) solo si fallan, para no tapar el resto.
	# `not_installed` no cuenta: la fila ya lo muestra con su botón Instalar…
	if job.background:
		if not job.is_done() or job.succeeded():
			return
		var err := GmParse.job_error(job)
		if err != null and err.code == "not_installed":
			return
	if not job in _jobs:
		_jobs.append(job)
		if _jobs.size() > GmCli.HISTORY_LIMIT:
			_jobs.pop_front()
	_queue_render()


func _queue_render() -> void:
	if _render_queued:
		return
	_render_queued = true
	_render.call_deferred()


func _render() -> void:
	_render_queued = false
	var parts: PackedStringArray = []
	for job in _jobs:
		parts.append(_job_text(job, true))
	_log.text = "\n".join(parts)
	_update_title()


func _update_title() -> void:
	var failed := _jobs.filter(func(j: CliJob) -> bool: return GmParse.job_error(j) != null and j.is_done()).size()
	var title := tr("Salida")
	if not _jobs.is_empty():
		title += " (%d)" % _jobs.size()
	if failed > 0:
		title += tr(" · %d con error") % failed
	_toggle.text = title


func _job_text(job: CliJob, bbcode: bool) -> String:
	var out: PackedStringArray = []
	out.append(_paint("$ " + job.command_line(), COLOR_CMD, bbcode))
	if not job.stdout.is_empty():
		out.append(_escape(_trim(job.stdout.trim_suffix("\n")), bbcode))
	if not job.stderr.is_empty():
		out.append(_paint(_trim(job.stderr.trim_suffix("\n")), COLOR_ERR, bbcode))
	out.append(_status_line(job, bbcode))
	return "\n".join(out)


func _status_line(job: CliJob, bbcode: bool) -> String:
	var secs := " (%.1f s)" % (job.duration_msec() / 1000.0)
	if job.start_error != null:
		return _paint(TranslationServer.translate("→ no arrancó: %s") % job.start_error.message, COLOR_ERR, bbcode)
	match job.state:
		CliJob.State.QUEUED:
			return _paint(tr("→ en cola…"), COLOR_DIM, bbcode)
		CliJob.State.RUNNING:
			return _paint(tr("→ corriendo…"), COLOR_DIM, bbcode)
	if job.cancelled:
		return _paint(tr("→ cancelado") + secs, COLOR_DIM, bbcode)
	return _paint(tr("→ código %d%s") % [job.exit_code, secs], COLOR_OK if job.exit_code == 0 else COLOR_ERR, bbcode)


static func _trim(text: String) -> String:
	if text.length() <= MAX_STREAM_CHARS:
		return text
	return text.left(MAX_STREAM_CHARS) + TranslationServer.translate("\n… (%d caracteres más)") % (text.length() - MAX_STREAM_CHARS)


static func _escape(text: String, bbcode: bool) -> String:
	return text.replace("[", "[lb]") if bbcode else text


static func _paint(text: String, color: String, bbcode: bool) -> String:
	if not bbcode:
		return text
	return "[color=%s]%s[/color]" % [color, _escape(text, true)]
