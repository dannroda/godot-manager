extends RefCounted
## De dónde vienen los plugins y qué releases tienen. Todo estático y sin red: recibe lo que
## contestaron las APIs y devuelve releases con la misma forma para todas las fuentes:
## `{version, id, stable, godot_min, godot_max, url, date}` (la más nueva primero).
##
## Fuentes:
## - `store:publisher/slug`: el Asset Store de Godot (store.godotengine.org). Cada release dice con
##   qué Godot anda; sus links de descarga vencen a los 10 minutos, así que se guarda el id.
## - `github:owner/repo`: los releases de un repo; el primer .zip adjunto, o el zip del código.

const Versions := preload("versions.gd")

const STORE_API := "https://store.godotengine.org/api/v1"
const GITHUB_API := "https://api.github.com"


## `{kind: "store"|"github", id: "a/b", name, source}` o `{error}`. Acepta las URLs de cada sitio
## y `a/b` solo (del Store).
static func parse(text: String) -> Dictionary:
	var t := text.strip_edges().trim_suffix("/")
	var kind := "store"
	for prefix: String in ["https://store.godotengine.org/asset/", "store:"]:
		if t.begins_with(prefix):
			t = t.trim_prefix(prefix)
	for prefix: String in ["https://github.com/", "http://github.com/", "github.com/", "github:"]:
		if t.begins_with(prefix):
			kind = "github"
			t = t.trim_prefix(prefix).trim_suffix(".git")
	var parts := t.split("/", false)
	if parts.size() < 2:
		return {"error": "invalid_source"}
	var id := "%s/%s" % [parts[0], parts[1]]
	if not _valid_id(id):
		return {"error": "invalid_source"}
	return {"kind": kind, "id": id, "name": parts[1].to_lower(), "source": "%s:%s" % [kind, id]}


## `fuente@versión` -> `[fuente, versión]` (sin @, versión "").
static func split_version(spec: String) -> PackedStringArray:
	var at := spec.rfind("@")
	if at <= 0:
		return PackedStringArray([spec, ""])
	return PackedStringArray([spec.left(at), spec.substr(at + 1)])


static func store_search_url(query: String, page: int, godot: String) -> String:
	var url := STORE_API + "/search/query/?query=%s&require_release=true&type=0&sort=relevance" % query.strip_edges().to_lower().uri_encode()
	if not godot.is_empty():
		url += "&compatibility=" + Versions.godot_number(godot)
	if page > 1:
		url += "&page=%d" % page
	return url


static func releases_url(source: Dictionary) -> String:
	if source.kind == "github":
		return GITHUB_API + "/repos/%s/releases?per_page=100" % source.id
	return STORE_API + "/releases/%s/" % source.id


static func details_url(source: Dictionary) -> String:
	if source.kind == "github":
		return GITHUB_API + "/repos/%s" % source.id
	return STORE_API + "/assets/%s/" % source.id


## Las releases que contestó la API de la fuente, normalizadas.
static func releases(source: Dictionary, data: Variant) -> Array:
	return github_releases(data) if source.kind == "github" else store_releases(data)


static func store_releases(data: Variant) -> Array:
	var result := []
	if not data is Array:
		return result
	for item: Variant in data:
		if not item is Dictionary or str(item.get("download_url", "")).is_empty():
			continue
		result.append({
			"version": str(item.get("version", "")),
			"id": str(int(item.id)) if item.get("id") is float or item.get("id") is int else _text(item.get("id")),
			"stable": bool(item.get("stable", true)),
			"godot_min": _text(item.get("min_godot_version")),
			"godot_max": _text(item.get("max_godot_version")),
			"url": str(item.download_url),
			"date": str(item.get("created", "")),
		})
	return result


static func github_releases(data: Variant) -> Array:
	var result := []
	if not data is Array:
		return result
	for item: Variant in data:
		if not item is Dictionary or bool(item.get("draft", false)):
			continue
		var url := ""
		for a: Variant in item.get("assets", []):
			if a is Dictionary and str(a.get("name", "")).to_lower().ends_with(".zip"):
				url = str(a.get("browser_download_url", ""))
				break
		if url.is_empty():
			url = _text(item.get("zipball_url"))
		if url.is_empty():
			continue
		result.append({
			"version": str(item.get("tag_name", "")),
			"id": str(item.get("tag_name", "")),
			"stable": not bool(item.get("prerelease", false)),
			"godot_min": "",
			"godot_max": "",
			"url": url,
			"date": str(item.get("published_at", "")).left(10),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Versions.compare(a.version, b.version) > 0)
	return result


## Las que andan con `godot` ("" = todas).
static func compatible(list: Array, godot: String) -> Array:
	return list.filter(func(r: Dictionary) -> bool: return Versions.godot_in_range(godot, r.godot_min, r.godot_max))


## La release a instalar: la `version` pedida (con o sin "v"), o la estable más nueva que anda con
## `godot` (o la más nueva que anda, si ninguna estable anda o con `prerelease`). {} si no hay.
static func pick(list: Array, godot: String, version: String = "", prerelease: bool = false) -> Dictionary:
	if not version.is_empty():
		for r: Dictionary in list:
			if Versions.same(r.version, version) or r.id == version:
				return r
		return {}
	var usable := compatible(list, godot)
	if not prerelease:
		for r: Dictionary in usable:
			if r.stable:
				return r
	return usable[0] if not usable.is_empty() else {}


## Una del Store por su id (para reinstalar lo del lock con un link nuevo). {} si no está.
static func by_id(list: Array, id: String) -> Dictionary:
	for r: Dictionary in list:
		if r.id == id:
			return r
	return {}


## `[{source, name, publisher, description, license, score, store_url}]` de una búsqueda del Store.
static func store_hits(data: Variant) -> Array:
	var result := []
	var hits: Variant = data.get("hits", []) if data is Dictionary else []
	if not hits is Array:
		return result
	for hit: Variant in hits:
		var a: Variant = hit.get("asset") if hit is Dictionary else null
		if not a is Dictionary:
			continue
		var publisher: Dictionary = a.get("publisher") if a.get("publisher") is Dictionary else {}
		var id := "%s/%s" % [publisher.get("slug", ""), a.get("slug", "")]
		if not _valid_id(id):
			continue
		result.append({
			"source": "store:" + id,
			"name": str(a.get("name", id)),
			"publisher": str(publisher.get("name", publisher.get("slug", ""))),
			"description": " ".join(str(a.get("description", "")).split("\n", false)).strip_edges().left(240),
			"license": _text(a.get("license_type")),
			"score": int(str(a.get("reviews_score", 0))),
			"price_cent": int(str(a.get("price_cent", 0))),
			"store_url": str(a.get("store_url", "")),
		})
	return result


static func _valid_id(id: String) -> bool:
	var parts := id.split("/", false)
	if parts.size() != 2:
		return false
	for part: String in parts:
		if not part.is_valid_filename() or part.begins_with(".") or part.contains(" "):
			return false
	return true


## str() de lo que puede venir null.
static func _text(value: Variant) -> String:
	return "" if value == null else str(value)
