extends ConfirmationDialog
## Proyecto nuevo: nombre, carpeta donde crearlo, versión de Godot (o la
## default), renderer y un preset de plugins opcional. No crea nada: emite
## `create_requested` con los argumentos de `new` y la carpeta del proyecto;
## la pantalla de proyectos lo corre y lo agrega a la lista.
## `open_with(parent_dir)` pide las versiones y los presets al CLI y lo muestra.

signal create_requested(args: PackedStringArray, path: String)

const RENDERERS: Array[Dictionary] = [
	{"id": "forward_plus", "label": "Forward+"},
	{"id": "mobile", "label": "Mobile"},
	{"id": "gl_compatibility", "label": "Compatibility"},
]

var versions: Array[InstalledVersion] = []
## Cómo se arma el nombre de la carpeta (DirNaming.Convention): la del editor
## de Godot, leída al abrir el diálogo.
var naming: int = DirNaming.DEFAULT
var presets: Array[PluginPreset] = []

@onready var _name: LineEdit = %ProjectName
@onready var _parent: LineEdit = %ParentDir
@onready var _browse: Button = %Browse
@onready var _browse_dialog: FileDialog = %BrowseDialog
@onready var _target: Label = %Target
@onready var _version: OptionButton = %Version
@onready var _renderer: OptionButton = %Renderer
@onready var _preset: OptionButton = %Preset
@onready var _preset_info: Label = %PresetInfo


func _ready() -> void:
	for i in RENDERERS.size():
		_renderer.add_item(RENDERERS[i].label, i)
	_name.text_changed.connect(func(_t: String) -> void: _validate())
	_parent.text_changed.connect(func(_t: String) -> void: _validate())
	_browse.pressed.connect(func() -> void:
		_browse_dialog.current_dir = _parent.text
		_browse_dialog.popup_centered_clamped(Vector2i(760, 480)))
	_browse_dialog.dir_selected.connect(func(dir: String) -> void:
		_parent.text = dir
		_validate())
	_preset.item_selected.connect(func(_i: int) -> void: _show_preset_info())
	confirmed.connect(func() -> void:
		if _validate():
			create_requested.emit(command(), target_path()))


func open_with(parent_dir: String) -> void:
	naming = DirNaming.read_convention()
	_name.text = ""
	_parent.text = parent_dir
	show_versions([])
	show_presets([])
	_validate()
	popup_centered_clamped(Vector2i(560, 360))
	_name.grab_focus()
	if not GmCli.available:
		return
	var list_job := GmCli.read(GmCommands.list())
	list_job.notify_on_error = false
	var presets_job := GmCli.read(GmCommands.presets())
	presets_job.notify_on_error = false
	await list_job.finished
	var r := GmParse.parse_list(list_job.stdout) if list_job.start_error == null else null
	show_versions(r.value if r != null and r.ok else [])
	if not presets_job.is_done():
		await presets_job.finished
	var rp := GmParse.parse_presets(presets_job.stdout) if presets_job.start_error == null else null
	show_presets(rp.value if rp != null and rp.ok else [])


## Las versiones para elegir: primero "la default" (sin .godot-version), después
## las oficiales de Godot 4 (las 3.x no sirven para `new`) y los builds propios.
func show_versions(list: Array) -> void:
	versions.clear()
	_version.clear()
	var default_name := ""
	for v: InstalledVersion in list:
		if v.is_default:
			default_name = v.name
	_version.add_item(tr("La default (%s)") % default_name if not default_name.is_empty() else tr("La default"))
	_version.set_item_metadata(0, "")
	for v: InstalledVersion in list:
		if not v.custom and GmParse.version_numbers(v.tag)[0] < 4:
			continue
		versions.append(v)
		_version.add_item(v.name)
		_version.set_item_metadata(_version.item_count - 1, v.name)


func show_presets(list: Array) -> void:
	presets.assign(list)
	_preset.clear()
	_preset.add_item(tr("Ninguno"))
	for p in presets:
		_preset.add_item(p.name)
	_preset.disabled = presets.is_empty()
	_show_preset_info()


func target_path() -> String:
	var parent := _parent.text.strip_edges()
	var name := _name.text.strip_edges()
	if parent.is_empty() or name.is_empty():
		return ""
	var dir := DirNaming.dir_name(name, naming)
	if dir.is_empty():
		return ""
	return parent.path_join(dir)


## Los argumentos de `new` con lo elegido.
func command() -> PackedStringArray:
	var version: String = _version.get_item_metadata(_version.selected) if _version.selected >= 0 else ""
	var preset := presets[_preset.selected - 1].name if _preset.selected > 0 else ""
	return GmCommands.new_project(target_path(), _name.text.strip_edges(), version,
		RENDERERS[maxi(_renderer.selected, 0)].id, preset)


func _validate() -> bool:
	var path := target_path()
	var problem := ""
	if _name.text.strip_edges().is_empty():
		problem = tr("Poné un nombre.")
	elif _parent.text.strip_edges().is_empty() or not DirAccess.dir_exists_absolute(_parent.text.strip_edges()):
		problem = tr("Elegí una carpeta que exista.")
	elif path.is_empty():
		problem = tr("El nombre no sirve para una carpeta.")
	elif DirAccess.dir_exists_absolute(path) and not _is_empty_dir(path):
		problem = tr("Ya hay una carpeta con archivos en %s.") % path
	_target.text = problem if not problem.is_empty() else tr("Se crea en %s") % path
	_target.tooltip_text = _target.text
	get_ok_button().disabled = not problem.is_empty()
	return problem.is_empty()


func _show_preset_info() -> void:
	if _preset.selected > 0:
		_preset_info.text = presets[_preset.selected - 1].summary()
	elif presets.is_empty():
		_preset_info.text = tr("No hay presets: se guardan desde los detalles de un proyecto (Presets → Guardar como preset…).")
	else:
		_preset_info.text = tr("Sin plugins.")


static func _is_empty_dir(path: String) -> bool:
	var dir := DirAccess.open(path)
	if dir == null:
		return false
	dir.include_hidden = true
	return dir.get_files().is_empty() and dir.get_directories().is_empty()
