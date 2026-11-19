extends TestCase
## Liberar espacio: lo que muestra de un `prune --dry-run` y el `prune` que
## arma al confirmar.

const DIALOG := preload("res://dialogs/prune_dialog.tscn")

var dialog: ConfirmationDialog


func before_each() -> void:
	dialog = DIALOG.instantiate()
	tree.root.add_child(dialog)


func after_each() -> void:
	dialog.queue_free()
	await wait_frames(1)


func _report(with_templates: bool) -> PruneReport:
	var r := PruneReport.new()
	var a := PruneReport.Candidate.new()
	a.version = "4.3-stable"
	a.size = 100 << 20
	if with_templates:
		a.templates_dir = "/t/4.3.stable"
		a.templates_size = 900 << 20
	var b := PruneReport.Candidate.new()
	b.version = "4.8-beta1-mono"
	b.size = 200 << 20
	r.candidates.assign([a, b])
	r.total = a.size + a.templates_size + b.size
	return r


func test_lists_versions_and_total() -> void:
	dialog.fill(_report(true))
	var list: ItemList = dialog.get_node("%List")
	assert_eq(list.item_count, 2)
	assert_has(list.get_item_text(0), "4.3-stable")
	assert_has(list.get_item_text(0), "export templates")
	assert_false(list.get_item_text(1).contains("templates"))
	assert_has((dialog.get_node("%Summary") as Label).text, String.humanize_size(1200 << 20))
	assert_false(dialog.get_ok_button().disabled)
	assert_eq(dialog.ok_button_text, "Borrar (2)")


func test_nothing_to_prune() -> void:
	dialog.fill(PruneReport.new())
	assert_eq((dialog.get_node("%List") as ItemList).item_count, 0)
	assert_has((dialog.get_node("%Summary") as Label).text, "No hay versiones sin usar")
	assert_true(dialog.get_ok_button().disabled)


func test_confirm_emits_prune_with_projects() -> void:
	dialog.projects = PackedStringArray(["/home/yo/juego"])
	dialog.fill(_report(false))
	var got: Array = []
	dialog.prune_requested.connect(func(args: PackedStringArray) -> void: got.append(args))
	dialog.confirmed.emit()
	assert_eq(got, [GmCommands.prune(PackedStringArray(["/home/yo/juego"]), false)])
