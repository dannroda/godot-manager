extends ConfirmationDialog
## Cambiar la versión de un proyecto: "Usar la default" o una de las
## instaladas (la actual marcada), con aviso si es más vieja que la de
## `config/features` y la línea de comando abajo. Escribe el .godot-version el
## CLI (`--dir <p> set-local <ver>` / `set-local --unset`), no la UI.
## `open_for(project, versions, status)` lo llena y lo muestra; al confirmar
## emite `change_requested` con los argumentos.

signal change_requested(args: PackedStringArray)

## Índice 0 de la lista: quitar el .godot-version.
const USE_DEFAULT := 0

var project: ProjectEntry
var versions: Array[InstalledVersion] = []
## Nombre fijado ahora ("" si usa la default o no se sabe).
var current := ""

@onready var _project_name: Label = %ProjectName
@onready var _list: ItemList = %Versions
@onready var _warning: Label = %Warning
@onready var _command: Label = %Command


func _ready() -> void:
	_list.item_selected.connect(func(_i: int) -> void: _update())
	_list.item_activated.connect(func(_i: int) -> void:
		if not get_ok_button().disabled:
			_confirm())
	confirmed.connect(func() -> void:
		var args := command()
		if not args.is_empty():
			change_requested.emit(args))


## `status` (de 3.2) dice cuál está fijada ahora; puede ser null.
func fill(p: ProjectEntry, installed: Array[InstalledVersion], status: ProjectStatus) -> void:
	project = p
	versions.assign(VersionFilter.apply(installed, "", VersionFilter.Kind.ALL))
	current = ""
	var default_name := ""
	for v in versions:
		if v.is_default:
			default_name = v.name
	if status != null and status.state == ProjectStatus.State.PINNED:
		current = status.resolution.version
	elif status != null and status.state == ProjectStatus.State.NOT_INSTALLED:
		current = status.missing_version()
	_project_name.text = p.name
	_project_name.tooltip_text = p.path
	_list.clear()
	var default_label := (tr("Usar la default (%s)") % default_name) if not default_name.is_empty() else tr("Usar la default")
	_list.add_item((tr("%s · actual") % default_label) if _uses_default(status) else default_label)
	_list.set_item_tooltip(USE_DEFAULT, tr("Quita el .godot-version del proyecto"))
	var select := USE_DEFAULT
	for v in versions:
		var i := _list.add_item((tr("%s · actual") % v.name) if v.name == current else v.name)
		_list.set_item_tooltip(i, v.path)
		if v.name == current:
			select = i
	_list.select(select)
	_update()


func open_for(p: ProjectEntry, installed: Array[InstalledVersion], status: ProjectStatus) -> void:
	fill(p, installed, status)
	reset_size()
	popup_centered()
	_list.grab_focus()
	_list.ensure_current_is_visible()


## La versión elegida (null = usar la default).
func chosen() -> InstalledVersion:
	var sel := _list.get_selected_items()
	if sel.is_empty() or sel[0] == USE_DEFAULT:
		return null
	return versions[sel[0] - 1]


## Los argumentos para el CLI, o vacío si no cambia nada.
func command() -> PackedStringArray:
	var v := chosen()
	if v == null:
		return GmCommands.unset_local(project.path) if not current.is_empty() else PackedStringArray()
	if v.name == current:
		return PackedStringArray()
	return GmCommands.set_local(project.path, v.name)


## true si `v` es de una versión menor (mayor.menor) que la de config/features.
static func older_than_project(v: InstalledVersion, p: ProjectEntry) -> bool:
	var made := p.created_with()
	if v == null or made.is_empty() or made == "3.x":
		return false
	var tag := v.tag if not v.tag.is_empty() else v.name
	var a := GmParse.version_numbers(tag)
	var b := GmParse.version_numbers(made)
	if a[0] == 0:
		return false  # Build propio sin número reconocible: no se sabe.
	return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])


func _uses_default(status: ProjectStatus) -> bool:
	return status != null and status.state == ProjectStatus.State.DEFAULT


func _update() -> void:
	var v := chosen()
	var older := older_than_project(v, project)
	_warning.text = (tr("El proyecto se guardó con Godot %s; abrirlo con %s puede perder datos o no abrir.") %
		[project.created_with(), v.name]) if older else ""
	_warning.visible = older
	var args := command()
	_command.text = CliJob.format_command(args) if not args.is_empty() else tr("(sin cambios)")
	# Sin reset_size(): si el aviso aparece el diálogo crece solo, y al
	# desaparecer no se achica (así los botones no saltan bajo el mouse).
	get_ok_button().disabled = args.is_empty()


func _confirm() -> void:
	hide()
	confirmed.emit()
