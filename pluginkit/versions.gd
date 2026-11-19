extends RefCounted
## Versiones de plugins y de Godot: comparar, y si una versión de Godot entra en el rango de una
## release. Acepta "v1.2.3", "1.2", "4.8-beta3" y sufijos de pre-release ("1.3.0-beta.1" < "1.3.0").


## -1, 0 o 1.
static func compare(a: String, b: String) -> int:
	var pa := _parts(a)
	var pb := _parts(b)
	for i in 3:
		if pa.numbers[i] != pb.numbers[i]:
			return 1 if pa.numbers[i] > pb.numbers[i] else -1
	if pa.pre == pb.pre:
		return 0
	if pa.pre.is_empty():
		return 1
	if pb.pre.is_empty():
		return -1
	return 1 if pa.pre > pb.pre else -1


## Si dos versiones son la misma escrita distinto ("v1.2" y "1.2.0").
static func same(a: String, b: String) -> bool:
	return compare(a, b) == 0


## Lo numérico de una versión de Godot: "4.5.1-stable" -> "4.5.1", "4.8-beta3" -> "4.8",
## "godot-4.3-custom" -> "4.3". "" si no tiene.
static func godot_number(version: String) -> String:
	var found := RegEx.create_from_string("(\\d+)\\.(\\d+)(?:\\.(\\d+))?").search(version)
	return found.get_string(0) if found else ""


## Si `godot` ("4.5.1"; "" = no se sabe) entra entre `low` y `high` ("" = sin cota). Cada cota se
## compara con su precisión: 4.7.2 entra en un máximo "4.7".
static func godot_in_range(godot: String, low: String, high: String) -> bool:
	if godot.is_empty():
		return true
	if not low.is_empty() and _compare_to_bound(godot, low) < 0:
		return false
	if not high.is_empty() and _compare_to_bound(godot, high) > 0:
		return false
	return true


static func _compare_to_bound(current: String, bound: String) -> int:
	var size := bound.strip_edges().split(".").size()
	var trimmed := ".".join(godot_number(current).split(".").slice(0, size))
	return compare(trimmed, bound)


static func _parts(version: String) -> Dictionary:
	var text := version.strip_edges().trim_prefix("v").trim_prefix("V")
	var pre := ""
	var dash := text.find("-")
	if dash >= 0:
		pre = text.substr(dash + 1)
		text = text.left(dash)
	var numbers := [0, 0, 0]
	var pieces := text.split(".")
	for i in mini(pieces.size(), 3):
		numbers[i] = pieces[i].to_int()
	return {"numbers": numbers, "pre": pre}
