extends TestCase


func _releases() -> Array[RemoteVersion]:
	var r := GmParse.parse_remote(FileAccess.get_file_as_string("res://tests/fixtures/list_remote.json"))
	var out: Array[RemoteVersion] = []
	out.assign(r.value)
	return out


static func _tags(list: Array[RemoteVersion]) -> Array:
	return list.map(func(r: RemoteVersion) -> String: return r.tag)


func _remote(tag: String, prerelease := false, published := "2026-01-01T00:00:00Z") -> RemoteVersion:
	var r := RemoteVersion.new()
	r.tag = tag
	r.prerelease = prerelease
	r.published_at = published
	return r


func _installed(name: String, tag: String, mono := false) -> InstalledVersion:
	var v := InstalledVersion.new()
	v.name = name
	v.tag = tag
	v.mono = mono
	v.custom = tag.is_empty()
	return v


func test_channels_sorted_by_version() -> void:
	var all := _releases()
	assert_eq(_tags(RemoteFilter.apply(all, "", RemoteFilter.Channel.ALL)),
		["4.8-beta3", "4.8-beta2", "4.7.2-stable", "3.6.3-stable"])
	assert_eq(_tags(RemoteFilter.apply(all, "", RemoteFilter.Channel.STABLE)), ["4.7.2-stable", "3.6.3-stable"])
	assert_eq(_tags(RemoteFilter.apply(all, "", RemoteFilter.Channel.DEV)), ["4.8-beta3", "4.8-beta2"])


func test_sort_ignores_publish_date() -> void:
	# 3.6.3 salió después que 4.7.2, pero va abajo; rc antes que beta; stable antes que rc.
	var list: Array[RemoteVersion] = [
		_remote("4.5-beta1", true, "2026-01-01T00:00:00Z"),
		_remote("4.5-stable", false, "2026-03-01T00:00:00Z"),
		_remote("3.6.3-stable", false, "2026-09-01T00:00:00Z"),
		_remote("4.5-rc2", true, "2026-02-01T00:00:00Z"),
		_remote("4.5.1-stable", false, "2026-04-01T00:00:00Z"),
	]
	assert_eq(_tags(RemoteFilter.apply(list, "", RemoteFilter.Channel.ALL)),
		["4.5.1-stable", "4.5-stable", "4.5-rc2", "4.5-beta1", "3.6.3-stable"])


func test_search() -> void:
	var all := _releases()
	assert_eq(_tags(RemoteFilter.apply(all, " BETA3 ", RemoteFilter.Channel.ALL)), ["4.8-beta3"])
	assert_eq(_tags(RemoteFilter.apply(all, "4.8", RemoteFilter.Channel.STABLE)), [], "búsqueda y canal juntos")
	assert_eq(RemoteFilter.apply(all, "nada", RemoteFilter.Channel.ALL).size(), 0)


func test_installed_marks() -> void:
	var installed: Array[InstalledVersion] = [
		_installed("4.8-beta3", "4.8-beta3"),
		_installed("4.7.2-stable", "4.7.2-stable"),
		_installed("4.7.2-stable-mono", "4.7.2-stable", true),
		_installed("4.6-mono", "4.6-stable", true),
		_installed("mi-build", ""),
	]
	var marks := RemoteFilter.installed_marks(installed)
	assert_eq(marks.keys(), ["4.8-beta3", "4.7.2-stable", "4.6-stable"], "los builds propios no cuentan")
	var m: RemoteFilter.Marks = marks["4.7.2-stable"]
	assert_true(m.normal and m.mono)
	m = marks["4.8-beta3"]
	assert_true(m.normal and not m.mono)
	m = marks["4.6-stable"]
	assert_true(m.mono and not m.normal)


func test_error_hint_for_token_problems() -> void:
	assert_has(RemoteFilter.error_hint(CliError.make("rate_limited", "la API de GitHub limito…")), "GITHUB_TOKEN")
	assert_has(RemoteFilter.error_hint(CliError.make("bad_token", "GitHub rechazo el token")), "Ajustes",
		"2.2: token inválido")
	assert_eq(RemoteFilter.error_hint(CliError.make("network", "sin red")), "")
	assert_eq(RemoteFilter.error_hint(null), "")


func test_day_and_url() -> void:
	assert_eq(RemoteFilter.day_of("2026-11-09T16:16:14Z"), "2026-11-09")
	assert_eq(RemoteFilter.day_of(""), "")
	var rel := RemoteVersion.new()
	rel.tag = "4.8-beta3"
	assert_eq(RemoteFilter.release_url(rel),
		"https://github.com/godotengine/godot-builds/releases/tag/4.8-beta3", "CLI anterior a 2.2: armada")
	rel.url = "https://github.com/godotengine/godot-builds/releases/tag/4.8-beta3-x"
	assert_eq(RemoteFilter.release_url(rel), rel.url, "2.2: la del CLI")
