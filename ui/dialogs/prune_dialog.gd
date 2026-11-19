extends ConfirmationDialog
## Liberar espacio: lista las versiones oficiales que no usa la default ni
## ningún proyecto (`prune --dry-run`) con lo que ocupan y, al confirmar,
## emite `prune_requested` con el `prune` que las borra.

signal prune_requested(args: PackedStringArray)

var report: PruneReport
## Carpetas de la lista de proyectos de la UI (el CLI suma las del Project
## Manager de Godot y la default).
var projects := PackedStringArray()

var _loading: CliJob

@onready var _summary: Label = %Summary
@onready var _list: ItemList = %List


func _ready() -> void:
	confirmed.connect(func() -> void:
		if report != null and not report.candidates.is_empty():
			prune_requested.emit(GmCommands.prune(projects, false)))


func open_with(p_projects: PackedStringArray) -> void:
	projects = p_projects
	report = null
	_list.clear()
	_summary.text = tr("Buscando versiones sin usar…")
	_update_ok()
	popup_centered()
	get_cancel_button().grab_focus()
	_loading = GmCli.read(GmCommands.prune(projects, true))
	_loading.notify_on_error = false
	var job := _loading
	await job.finished
	if job != _loading or not visible:
		return
	var r := GmParse.parse_prune(job.stdout) if job.succeeded() else null
	if r != null and r.ok:
		fill(r.value)
	else:
		var err := GmParse.job_error(job) if r == null else r.error
		_summary.text = tr("No se pudo calcular:\n%s") % (err.message if err != null else "")


## Muestra un resultado de `prune --dry-run`.
func fill(r: PruneReport) -> void:
	report = r
	_list.clear()
	for c in r.candidates:
		var size := String.humanize_size(c.size)
		if c.templates_dir.is_empty():
			_list.add_item("%s — %s" % [c.version, size])
		else:
			_list.add_item(tr("%s — %s + export templates (%s)") % [c.version, size,
				String.humanize_size(c.templates_size)])
		_list.set_item_tooltip(_list.item_count - 1, c.templates_dir)
	if r.candidates.is_empty():
		_summary.text = tr("No hay versiones sin usar: todas son la default o las usa algún proyecto.")
	else:
		_summary.text = tr("Estas versiones no las usa la default ni ningún proyecto de la lista o del Project Manager de Godot. Se liberan %s.") \
			% String.humanize_size(r.total)
	_update_ok()


func _update_ok() -> void:
	var n := 0 if report == null else report.candidates.size()
	get_ok_button().disabled = n == 0
	ok_button_text = tr("Borrar (%d)") % n if n > 0 else tr("Borrar")
