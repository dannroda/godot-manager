extends PanelContainer
## Tarjeta de la barra lateral para las escrituras largas (install, templates, symbols):
## título, barra, la última línea del CLI, avisos y Cancelar. Con eventos
## `download` la barra muestra el avance real; si no, queda indeterminada.
## No llama al CLI por su cuenta salvo `run` (GmCli.write); `track` sigue un
## job ya lanzado (lo usan los tests). Si el CLI pide confirmación
## (`needs_confirmation`, más de 1 GB), pregunta y repite con `--yes`.

const NEEDS_CONFIRMATION := "needs_confirmation"
## Cuánto queda a la vista el resultado ("Listo. Templates instalados: …").
const RESULT_SECONDS := 5.0

## Jobs seguidos, en orden: [{job: CliJob, title: String, warnings: Array}].
var _entries: Array[Dictionary] = []
var _confirm_args := PackedStringArray()
var _confirm_title := ""
## El job por el que se está preguntando "¿Cancelar?".
var _cancel_target: CliJob
## El último que terminó bien, mientras no haya otro en curso: {title, status}.
var _result := {}
var _result_serial := 0

@onready var _title: Label = %JobTitle
@onready var _queue: Label = %Queue
@onready var _progress: ProgressBar = %Progress
@onready var _status: Label = %Status
@onready var _warnings: Label = %Warnings
@onready var _cancel: Button = %Cancel
@onready var _cancel_dialog: ConfirmationDialog = %CancelDialog
@onready var _confirm_dialog: ConfirmationDialog = %ConfirmDialog


func _ready() -> void:
	visible = false
	_cancel.pressed.connect(func() -> void:
		var e := current()
		if e.is_empty():
			return
		_cancel_target = e["job"]
		_cancel_dialog.dialog_text = tr("¿Cancelar «%s»?\nEl proceso se corta ya; si estaba descargando, puede quedar el archivo a medias en la carpeta temporal.") % e["title"]
		_cancel_dialog.popup_centered())
	_cancel_dialog.confirmed.connect(func() -> void:
		if _cancel_target != null and not _cancel_target.is_done():
			GmCli.cancel(_cancel_target)
		_cancel_target = null)
	_cancel_dialog.canceled.connect(func() -> void: _cancel_target = null)
	_confirm_dialog.confirmed.connect(func() -> void:
		var args := _confirm_args.duplicate()
		args.append("--yes")
		run(args, _confirm_title))


## Lanza la escritura y la sigue.
func run(args: PackedStringArray, title: String) -> CliJob:
	var job := GmCli.write(args)
	track(job, title)
	return job


func track(job: CliJob, title: String) -> void:
	var entry := {"job": job, "title": title, "warnings": []}
	_entries.append(entry)
	job.line_received.connect(func(stream: CliJob.Stream, text: String) -> void:
		_on_line(entry, stream, text))
	job.finished.connect(func(_j: CliJob) -> void: _on_finished(entry), CONNECT_ONE_SHOT)
	if job.is_done():
		_on_finished(entry)
	else:
		_refresh()


## El que se muestra: el primero que no terminó ({} si no hay).
func current() -> Dictionary:
	for e in _entries:
		if not (e["job"] as CliJob).is_done():
			return e
	return {}


func _on_line(entry: Dictionary, stream: CliJob.Stream, text: String) -> void:
	var line := text.strip_edges()
	if line.is_empty():
		return
	var r := GmParse.parse_event(line) if stream == CliJob.Stream.STDOUT else null
	if r == null or not r.ok:
		# stderr o una línea que no es JSON (CLI viejo): se muestra como texto.
		entry["status"] = line
		entry.erase("progress")
	else:
		var ev: CliEvent = r.value
		match ev.kind:
			CliEvent.Kind.STEP:
				entry["status"] = ev.message
			CliEvent.Kind.DOWNLOAD:
				entry["progress"] = ev.progress()
				entry["status"] = describe_download(ev)
			CliEvent.Kind.WARN:
				(entry["warnings"] as Array).append(ev.message)
			CliEvent.Kind.DONE:
				entry["status"] = describe_done(ev)
				entry["progress"] = 1.0
	if entry == current():
		_refresh()


func _on_finished(entry: Dictionary) -> void:
	var job: CliJob = entry["job"]
	_entries.erase(entry)
	# Terminó mientras se preguntaba si cancelarlo: la pregunta ya no aplica.
	if job == _cancel_target:
		_cancel_target = null
		_cancel_dialog.hide()
	var err := GmParse.job_error(job)
	if job.succeeded():
		_show_result(entry)
	if err != null and err.code == NEEDS_CONFIRMATION and not job.cancelled:
		_confirm_args = job.args
		_confirm_title = entry["title"]
		_confirm_dialog.dialog_text = err.message + tr("\n\n¿Seguir con la descarga?")
		_confirm_dialog.popup_centered()
	_refresh()


## Deja el resultado a la vista unos segundos (si no arranca otro antes).
func _show_result(entry: Dictionary) -> void:
	_result = {"title": entry["title"], "status": entry.get("status", tr("Listo.")),
		"warnings": entry["warnings"]}
	_result_serial += 1
	var serial := _result_serial
	get_tree().create_timer(RESULT_SECONDS).timeout.connect(func() -> void:
		if serial == _result_serial:
			_result = {}
			_refresh())


func _refresh() -> void:
	var e := current()
	_cancel.visible = not e.is_empty()
	if e.is_empty() and not _result.is_empty():
		visible = true
		_title.text = _result["title"]
		_queue.text = ""
		_progress.indeterminate = false
		_progress.value = 100.0
		_status.text = _result["status"]
		_show_warnings(_result["warnings"])
		return
	visible = not e.is_empty()
	if e.is_empty():
		return
	_result = {}
	var job: CliJob = e["job"]
	var waiting := job.state == CliJob.State.QUEUED
	_title.text = e["title"]
	var more := 0
	for other in _entries:
		if other != e and not (other["job"] as CliJob).is_done():
			more += 1
	_queue.text = tr("(+%d en cola)") % more if more > 0 else ""
	var p: float = e.get("progress", -1.0)
	# Sin porcentaje en la barra: la tarjeta es angosta y el estado ya lo dice.
	_progress.indeterminate = p < 0.0
	if p >= 0.0:
		_progress.value = p * 100.0
	_status.text = tr("Esperando a que termine otra operación…") if waiting else e.get("status", tr("Arrancando…"))
	_show_warnings(e["warnings"])


func _show_warnings(warnings: Array) -> void:
	_warnings.text = "\n".join(warnings.map(func(w: String) -> String: return "⚠ " + w))
	_warnings.visible = not warnings.is_empty()


## "Godot_v4.8-beta3_linux.x86_64.zip — 12.3 MiB de 59.5 MiB (21%)".
static func describe_download(ev: CliEvent) -> String:
	if ev.total <= 0:
		return "%s — %s" % [ev.file, String.humanize_size(ev.done)]
	return "%s — %s de %s (%d%%)" % [ev.file, String.humanize_size(ev.done),
		String.humanize_size(ev.total), roundi(ev.progress() * 100.0)]


## Texto del `done`; si trae `platforms` (templates), cuáles quedaron.
static func describe_done(ev: CliEvent) -> String:
	var platforms: Variant = ev.data.get("platforms")
	if platforms is Array and not (platforms as Array).is_empty():
		return TranslationServer.translate("Listo. Templates instalados: %s") % ", ".join(PackedStringArray(platforms))
	return TranslationServer.translate("Listo.")
