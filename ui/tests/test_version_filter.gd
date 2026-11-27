extends TestCase


func _fixture_versions() -> Array[InstalledVersion]:
	var r := GmParse.parse_list(FileAccess.get_file_as_string("res://tests/fixtures/list.json"))
	var out: Array[InstalledVersion] = []
	out.assign(r.value)
	return out


static func _names(list: Array[InstalledVersion]) -> Array:
	return list.map(func(v: InstalledVersion) -> String: return v.name)


func test_default_order_newest_first() -> void:
	var shown := VersionFilter.apply(_fixture_versions(), "", VersionFilter.Kind.ALL)
	assert_eq(_names(shown), ["4.8-beta3", "4.8-beta2", "4.8-beta1", "4.7.2-stable",
		"4.7.2-stable-mono", "4.5.1-stable"])


func test_search() -> void:
	var v := _fixture_versions()
	assert_eq(VersionFilter.apply(v, "beta", VersionFilter.Kind.ALL).size(), 3)
	assert_eq(VersionFilter.apply(v, "  BETA2 ", VersionFilter.Kind.ALL).size(), 1, "sin mayúsculas ni espacios")
	assert_eq(VersionFilter.apply(v, "/opt/godot/versions/4.5", VersionFilter.Kind.ALL).size(), 1, "busca en la ruta")
	assert_eq(VersionFilter.apply(v, "nada", VersionFilter.Kind.ALL).size(), 0)


func test_kinds() -> void:
	var v := _fixture_versions()
	assert_eq(_names(VersionFilter.apply(v, "", VersionFilter.Kind.MONO)), ["4.7.2-stable-mono"])
	assert_eq(VersionFilter.apply(v, "", VersionFilter.Kind.SYMBOLS).size(), 3)
	assert_eq(VersionFilter.apply(v, "", VersionFilter.Kind.CUSTOM).size(), 0)
	assert_eq(VersionFilter.apply(v, "beta3", VersionFilter.Kind.MONO).size(), 0, "búsqueda y filtro juntos")


func test_custom_builds_sort_by_name_as_version() -> void:
	var a := InstalledVersion.new()
	a.name = "4.10-mio"
	a.custom = true
	var b := InstalledVersion.new()
	b.name = "4.9-stable"
	b.tag = "4.9-stable"
	var list: Array[InstalledVersion] = [b, a]
	assert_eq(_names(VersionFilter.apply(list, "", VersionFilter.Kind.ALL)), ["4.10-mio", "4.9-stable"])


func test_series_and_groups() -> void:
	var make := func(name: String, custom := false) -> InstalledVersion:
		var v := InstalledVersion.new()
		v.name = name
		v.custom = custom
		v.tag = "" if custom else name
		return v
	assert_eq(VersionFilter.series(make.call("4.8-beta3")), "4.8")
	assert_eq(VersionFilter.series(make.call("4.7.2-stable")), "4.7")
	assert_eq(VersionFilter.series(make.call("4.7.2-stable-mono")), "4.7")
	assert_eq(VersionFilter.series(make.call("mi-build", true)), "")
	var shown: Array[InstalledVersion] = [make.call("4.8-beta3"), make.call("mi-build", true),
		make.call("4.7.2-stable"), make.call("4.7.1-stable")]
	var groups := VersionFilter.group_by_series(shown)
	var titles: Array[String] = []
	for g: Array in groups:
		titles.append(g[0])
	assert_eq(titles, ["4.8", "4.7", ""] as Array[String], "los builds propios al final")
	assert_eq((groups[1][1] as Array).size(), 2)
