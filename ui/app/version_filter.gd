class_name VersionFilter
extends RefCounted
## Búsqueda, filtro y orden de las versiones instaladas, sin UI (se testea sola).

enum Kind { ALL, MONO, SYMBOLS, CUSTOM }

const KIND_LABELS := {
	Kind.ALL: "Todas",
	Kind.MONO: "Mono",
	Kind.SYMBOLS: "Con símbolos",
	Kind.CUSTOM: "Builds propios",
}


## Las que coinciden con `query` (en nombre, tag o ruta, sin mayúsculas) y con
## `kind`, de la más nueva a la más vieja.
static func apply(versions: Array[InstalledVersion], query: String, kind: Kind) -> Array[InstalledVersion]:
	var q := query.strip_edges().to_lower()
	var out: Array[InstalledVersion] = []
	for v in versions:
		if not _matches_kind(v, kind):
			continue
		if not q.is_empty() and not (v.name.to_lower().contains(q) or v.tag.to_lower().contains(q) \
				or v.path.to_lower().contains(q)):
			continue
		out.append(v)
	out.sort_custom(is_before)
	return out


## Orden de la lista: por versión, la más nueva arriba; a igual versión, la
## que no es mono primero y después por nombre.
static func is_before(a: InstalledVersion, b: InstalledVersion) -> bool:
	var ta := a.tag if not a.tag.is_empty() else a.name
	var tb := b.tag if not b.tag.is_empty() else b.name
	if GmParse.is_newer(ta, tb):
		return true
	if GmParse.is_newer(tb, ta):
		return false
	if a.mono != b.mono:
		return not a.mono
	return a.name < b.name


static func _matches_kind(v: InstalledVersion, kind: Kind) -> bool:
	match kind:
		Kind.MONO:
			return v.mono
		Kind.SYMBOLS:
			return v.debug_symbols
		Kind.CUSTOM:
			return v.custom
	return true
