extends TestCase
## Prueba los asserts de TestCase y el fixture del CLI.


func test_assert_eq_records_without_aborting() -> void:
	var inner := TestCase.new()
	inner.assert_eq(1, 2)
	inner.assert_eq("a", "a")
	inner.assert_true(false, "segunda")
	assert_eq(inner._get_failures().size(), 2, "dos fallas registradas")
	assert_has(inner._get_failures()[1], "segunda")


func test_assert_eq_numbers_and_types() -> void:
	var inner := TestCase.new()
	assert_true(inner.assert_eq(3, 3.0), "int y float iguales")
	assert_false(inner.assert_eq("1", 1), "string contra int")
	assert_true(inner.assert_eq([1, "x"], [1, "x"]))


func test_skip_reason() -> void:
	var inner := TestCase.new()
	inner.skip("motivo")
	assert_eq(inner._get_skip_reason(), "motivo")


## Falla a propósito solo con GM_TEST_SELFCHECK=1, para comprobar que el runner
## informa la falla y sale con código 1.
func test_selfcheck_failure() -> void:
	if OS.get_environment("GM_TEST_SELFCHECK") != "1":
		skip("solo con GM_TEST_SELFCHECK=1")
		return
	assert_eq("falla", "a propósito")


func test_fixture_lists_fake_versions() -> void:
	var fx := CliFixture.new()
	if not fx.available():
		skip(fx.why_unavailable())
		return
	if not assert_true(fx.setup(["4.2-fake", "4.3-fake"]), fx.last_error):
		fx.teardown()
		return
	var root := fx.root
	var data: Variant = fx.run_json(["--json", "list"])
	if assert_true(data is Dictionary, "list devuelve un objeto"):
		var names: Array = (data["versions"] as Array).map(func(v: Dictionary) -> String: return v["name"])
		assert_eq(names, ["4.2-fake", "4.3-fake"])
	fx.teardown()
	assert_false(DirAccess.dir_exists_absolute(root), "teardown borra la carpeta")
	assert_ne(OS.get_environment("GODOT_DIR"), root, "teardown restaura GODOT_DIR")
