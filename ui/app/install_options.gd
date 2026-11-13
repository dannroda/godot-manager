class_name InstallOptions
extends RefCounted
## Lo elegido en el diálogo de instalación, y el comando que sale de eso. El
## diálogo muestra `command()` como vista previa y es lo mismo que se corre,
## así no pueden diferir. Sin UI (se testea sola).

## INSTALL: `install <tag>` (editor + opcionalmente templates).
## TEMPLATES: `templates <tag>` para una versión ya instalada (2.5).
enum Mode { INSTALL, TEMPLATES }

var mode := Mode.INSTALL
var version := ""
var mono := false
var debug_symbols := false
## Solo en INSTALL: si además se instalan export templates.
var with_templates := false
var platforms: PackedStringArray = GmCommands.PLATFORMS.duplicate()


## Opciones para agregar templates a una versión instalada: el tag oficial y
## si es mono salen de la versión; sin tildar las plataformas que ya tiene.
static func for_templates(v: InstalledVersion) -> InstallOptions:
	var o := InstallOptions.new()
	o.mode = Mode.TEMPLATES
	o.version = tag_of(v)
	o.mono = v.mono
	var missing: PackedStringArray = []
	for p in GmCommands.PLATFORMS:
		if not p in v.template_platforms:
			missing.append(p)
	o.platforms = missing
	return o


## El tag oficial de una versión instalada. `list --json` lo trae (C.6); si
## falta (CLI anterior), provisorio: el nombre sin `-mono`, como hace el CLI.
static func tag_of(v: InstalledVersion) -> String:
	if not v.tag.is_empty():
		return v.tag
	return v.name.trim_suffix("-mono")


func wants_templates() -> bool:
	return mode == Mode.TEMPLATES or with_templates


## Con todas las plataformas va `--templates` (o nada, en TEMPLATES); con
## algunas, solo `--platforms=…`, que para el CLI ya implica templates.
func command() -> PackedStringArray:
	var all := _all_platforms()
	var subset: PackedStringArray = []
	if not all:
		subset = _ordered_platforms()
	if mode == Mode.TEMPLATES:
		return GmCommands.templates(version, mono, subset, debug_symbols)
	if not with_templates:
		return GmCommands.install(version, mono, debug_symbols)
	return GmCommands.install(version, mono, debug_symbols, all, subset)


## Por qué no se puede confirmar todavía ("" si se puede).
func problem() -> String:
	if version.is_empty():
		return "No hay versión elegida."
	if wants_templates() and platforms.is_empty():
		return "Elegí al menos una plataforma para los templates."
	return ""


## Bytes a bajar según `release` (0 si el CLI no informa tamaños).
func download_size(release: RemoteVersion) -> int:
	if release == null:
		return 0
	var total := 0
	if mode == Mode.INSTALL:
		total += release.mono_size if mono else release.editor_size
	if wants_templates():
		total += release.templates_size
	return total


func _all_platforms() -> bool:
	for p in GmCommands.PLATFORMS:
		if not p in platforms:
			return false
	return true


## Las elegidas, en el orden de GmCommands.PLATFORMS.
func _ordered_platforms() -> PackedStringArray:
	var out: PackedStringArray = []
	for p in GmCommands.PLATFORMS:
		if p in platforms:
			out.append(p)
	return out
