class_name RemoteFilter
extends RefCounted
## Filtro, búsqueda y orden de las versiones remotas, y el cruce con las
## instaladas. Sin UI (se testea sola).

enum Channel { ALL, STABLE, DEV }

const CHANNEL_LABELS := {
	Channel.STABLE: "Stable",
	Channel.DEV: "Dev",
	Channel.ALL: "Todas",
}

## Qué hay instalado de un tag: el editor normal, el mono, o los dos.
class Marks:
	var normal := false
	var mono := false


## Las que coinciden con `query` (en el tag, sin mayúsculas) y con `channel`,
## de la más nueva a la más vieja por versión (el CLI las da por fecha).
static func apply(releases: Array[RemoteVersion], query: String, channel: Channel) -> Array[RemoteVersion]:
	var q := query.strip_edges().to_lower()
	var out: Array[RemoteVersion] = []
	for r in releases:
		if channel == Channel.STABLE and r.prerelease:
			continue
		if channel == Channel.DEV and not r.prerelease:
			continue
		if not q.is_empty() and not r.tag.to_lower().contains(q):
			continue
		out.append(r)
	out.sort_custom(is_before)
	return out


static func is_before(a: RemoteVersion, b: RemoteVersion) -> bool:
	if GmParse.is_newer(a.tag, b.tag):
		return true
	if GmParse.is_newer(b.tag, a.tag):
		return false
	return a.published_at > b.published_at


## tag → Marks, con las versiones oficiales instaladas (los builds propios
## no cuentan: no tienen tag).
static func installed_marks(installed: Array[InstalledVersion]) -> Dictionary:
	var out := {}
	for v in installed:
		if v.tag.is_empty():
			continue
		var m: Marks = out.get(v.tag)
		if m == null:
			m = Marks.new()
			out[v.tag] = m
		if v.mono:
			m.mono = true
		else:
			m.normal = true
	return out


## Sugerencia que va debajo del error del CLI (sin reescribirlo), o "".
static func error_hint(err: CliError) -> String:
	if err == null:
		return ""
	match err.code:
		"rate_limited":
			return "Cargá un GITHUB_TOKEN en Ajustes para subir el límite de pedidos a GitHub."
		"bad_token":
			return "GitHub rechazó el GITHUB_TOKEN: revisalo o borralo en Ajustes."
	return ""


## "2026-11-09T16:16:14Z" → "2026-11-09".
static func day_of(published_at: String) -> String:
	return published_at.get_slice("T", 0)


## Página de la release en GitHub: la que da el CLI (2.2+, campo `url`) o,
## con un CLI anterior, armada a partir del tag.
static func release_url(rel: RemoteVersion) -> String:
	if not rel.url.is_empty():
		return rel.url
	return "https://github.com/godotengine/godot-builds/releases/tag/" + rel.tag.uri_encode()
