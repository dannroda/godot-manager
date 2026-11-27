class_name ListFocus
extends RefCounted
## Foco con teclado en las listas de filas (SelectableRow): a qué fila ir al
## entrar desde la búsqueda o al cambiar de pestaña.


## Da el foco a la fila seleccionada, o a la primera visible; si no hay filas,
## a `fallback` (la búsqueda). Al tomar el foco la fila se selecciona sola.
static func focus_rows(rows: Container, fallback: Control) -> void:
	var first: Control = null
	for row: Control in rows.get_children():
		# Los títulos de grupo (Versiones) no son filas.
		if not row is SelectableRow or not row.visible or row.is_queued_for_deletion():
			continue
		if row.get("is_selected"):
			row.grab_focus()
			return
		if first == null:
			first = row
	if first != null:
		first.grab_focus()
	elif fallback != null and fallback.is_visible_in_tree():
		fallback.grab_focus()


## Ctrl+F: foco a la búsqueda con el texto elegido, para escribir encima.
static func focus_search(search: LineEdit) -> void:
	search.grab_focus()
	search.select_all()
