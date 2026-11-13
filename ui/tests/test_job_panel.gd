extends TestCase
## Panel de progreso, alimentado con jobs falsos (CliJob sin proceso): qué
## muestra con cada evento, la cola y el pedido de confirmación.

const PANEL := preload("res://panels/job_panel.tscn")

var panel: PanelContainer


func before_each() -> void:
	panel = PANEL.instantiate()
	tree.root.add_child(panel)


func after_each() -> void:
	panel.queue_free()
	await wait_frames(1)


func _job(state := CliJob.State.RUNNING) -> CliJob:
	var job := CliJob.new(GmCommands.install("4.8-beta3"), CliJob.Kind.WRITE)
	job.state = state
	return job


func _out(job: CliJob, line: String) -> void:
	job.line_received.emit(CliJob.Stream.STDOUT, line)


func _end(job: CliJob, code: int, stdout := "") -> void:
	job.exit_code = code
	job.stdout = stdout
	job.state = CliJob.State.DONE
	job.finished.emit(job)


func _text(name: String) -> String:
	return (panel.get_node("%" + name) as Label).text


func _bar() -> ProgressBar:
	return panel.get_node("%Progress")


func test_hidden_until_tracking() -> void:
	assert_false(panel.visible)
	var job := _job()
	panel.track(job, "Instalando 4.8-beta3")
	assert_true(panel.visible)
	assert_eq(_text("JobTitle"), "Instalando 4.8-beta3")
	assert_true(_bar().indeterminate, "sin eventos de descarga, indeterminada")
	_out(job, '{"event":"done","version":"4.8-beta3","platforms":["linux"]}')
	_end(job, 0)
	assert_true(panel.visible, "el resultado queda a la vista un rato")
	assert_eq(_text("Status"), "Listo. Templates instalados: linux")
	assert_false((panel.get_node("%Cancel") as Button).visible, "ya no hay nada que cancelar")


func test_result_replaced_by_next_job() -> void:
	var a := _job()
	panel.track(a, "Instalando A")
	_end(a, 0)
	var b := _job()
	panel.track(b, "Instalando B")
	assert_eq(_text("JobTitle"), "Instalando B")
	assert_true((panel.get_node("%Cancel") as Button).visible)
	_end(b, 1, '{"event":"error","code":"network","message":"sin red"}\n')
	assert_false(panel.visible, "si falla no queda resultado: el error lo muestra main")


func test_events() -> void:
	var job := _job()
	panel.track(job, "Instalando 4.8-beta3")
	_out(job, '{"event":"step","message":"Verificando checksum"}')
	assert_eq(_text("Status"), "Verificando checksum")
	_out(job, '{"event":"download","file":"Godot.zip","done":524288,"total":2097152}')
	assert_false(_bar().indeterminate)
	assert_eq(_bar().value, 25.0)
	assert_eq(_text("Status"), "Godot.zip — 512.0 KiB de 2.00 MiB (25%)")
	_out(job, '{"event":"warn","message":"mono + web no existe en 4.5.1"}')
	assert_true((panel.get_node("%Warnings") as Label).visible)
	assert_eq(_text("Warnings"), "⚠ mono + web no existe en 4.5.1")
	_out(job, "esto no es json")
	assert_eq(_text("Status"), "esto no es json", "CLI viejo: la línea tal cual")
	assert_true(_bar().indeterminate)
	job.line_received.emit(CliJob.Stream.STDERR, "Aviso: algo")
	assert_eq(_text("Status"), "Aviso: algo")


func test_done_lists_platforms() -> void:
	var ev: CliEvent = GmParse.parse_event('{"event":"done","version":"4.8-beta3","platforms":["linux","windows"]}').value
	assert_eq(panel.describe_done(ev), "Listo. Templates instalados: linux, windows")
	ev = GmParse.parse_event('{"event":"done","version":"4.8-beta3"}').value
	assert_eq(panel.describe_done(ev), "Listo.")


func test_queue() -> void:
	var a := _job()
	var b := _job(CliJob.State.QUEUED)
	panel.track(a, "Instalando A")
	panel.track(b, "Instalando B")
	assert_eq(_text("JobTitle"), "Instalando A")
	assert_eq(_text("Queue"), "(+1 en cola)")
	_end(a, 0)
	assert_eq(_text("JobTitle"), "Instalando B")
	assert_eq(_text("Queue"), "")
	assert_eq(_text("Status"), "Esperando a que termine otra operación…")


func test_needs_confirmation_asks() -> void:
	var job := _job()
	panel.track(job, "Instalando 4.8-beta3")
	_end(job, 1, '{"event":"error","code":"needs_confirmation","message":"Se van a descargar 1.4 GB."}\n')
	var dialog: ConfirmationDialog = panel.get_node("%ConfirmDialog")
	assert_true(dialog.visible)
	assert_true(dialog.dialog_text.begins_with("Se van a descargar 1.4 GB."))
	dialog.hide()


func test_cancel_question_closes_if_job_ends() -> void:
	var job := _job()
	panel.track(job, "Instalando 4.2-beta1")
	(panel.get_node("%Cancel") as Button).pressed.emit()
	var dialog: ConfirmationDialog = panel.get_node("%CancelDialog")
	assert_true(dialog.visible)
	_end(job, 0)
	assert_false(dialog.visible, "terminó solo: la pregunta se cierra")


func test_other_errors_do_not_ask() -> void:
	var job := _job()
	panel.track(job, "Instalando 9.9")
	_end(job, 1, '{"event":"error","code":"not_found","message":"no existe"}\n')
	assert_false((panel.get_node("%ConfirmDialog") as Window).visible)
	assert_false(panel.visible)
