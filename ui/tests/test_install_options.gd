extends TestCase


func _opts(version := "4.8-beta3") -> InstallOptions:
	var o := InstallOptions.new()
	o.version = version
	return o


func _line(o: InstallOptions) -> String:
	return CliJob.format_command(o.command(), "godot-manager", false)


func test_plain_install() -> void:
	assert_eq(_line(_opts("4.3-stable")), "godot-manager --json install 4.3-stable")


func test_mono_and_symbols() -> void:
	var o := _opts()
	o.mono = true
	assert_eq(_line(o), "godot-manager --json install 4.8-beta3 --mono")
	o.debug_symbols = true
	assert_eq(_line(o), "godot-manager --json install 4.8-beta3 --mono --debugsymbols")
	o.mono = false
	assert_eq(_line(o), "godot-manager --json install 4.8-beta3 --debugsymbols")


func test_templates_all_platforms() -> void:
	var o := _opts()
	o.with_templates = true
	assert_eq(_line(o), "godot-manager --json install 4.8-beta3 --templates")


func test_templates_subset_in_canonical_order() -> void:
	var o := _opts()
	o.with_templates = true
	o.mono = true
	o.debug_symbols = true
	o.platforms = PackedStringArray(["windows", "linux"])
	assert_eq(_line(o), "godot-manager --json install 4.8-beta3 --mono --debugsymbols --platforms=linux,windows")


func test_platforms_ignored_without_templates() -> void:
	var o := _opts()
	o.platforms = PackedStringArray(["web"])
	assert_eq(_line(o), "godot-manager --json install 4.8-beta3")
	assert_eq(o.problem(), "")


func test_no_platforms_is_a_problem() -> void:
	var o := _opts()
	o.with_templates = true
	o.platforms = PackedStringArray()
	assert_ne(o.problem(), "")
	o.with_templates = false
	assert_eq(o.problem(), "")
	assert_ne(_opts("").problem(), "", "sin versión")


func test_templates_mode() -> void:
	var o := _opts("4.7.2-stable")
	o.mode = InstallOptions.Mode.TEMPLATES
	assert_eq(_line(o), "godot-manager --json templates 4.7.2-stable")
	o.mono = true
	o.debug_symbols = true
	o.platforms = PackedStringArray(["linux"])
	assert_eq(_line(o), "godot-manager --json templates 4.7.2-stable --mono --platforms=linux --debugsymbols")
	o.platforms = PackedStringArray()
	assert_ne(o.problem(), "", "en modo templates siempre hace falta una plataforma")


func _installed(name: String, tag: String, mono := false, platforms: PackedStringArray = []) -> InstalledVersion:
	var v := InstalledVersion.new()
	v.name = name
	v.tag = tag
	v.mono = mono
	v.template_platforms = platforms
	return v


func test_for_templates_normal_and_mono() -> void:
	var o := InstallOptions.for_templates(_installed("4.7.2-stable", "4.7.2-stable"))
	assert_eq(_line(o), "godot-manager --json templates 4.7.2-stable")
	o = InstallOptions.for_templates(_installed("4.7.2-stable-mono", "4.7.2-stable", true))
	o.platforms = PackedStringArray(["linux"])
	assert_eq(_line(o), "godot-manager --json templates 4.7.2-stable --mono --platforms=linux")


func test_tag_without_c6_comes_from_name() -> void:
	assert_eq(InstallOptions.tag_of(_installed("4.7.2-stable-mono", "", true)), "4.7.2-stable")
	assert_eq(InstallOptions.tag_of(_installed("4.5-stable", "")), "4.5-stable")
	assert_eq(InstallOptions.tag_of(_installed("4.5-mi-mono", "4.5-stable", true)), "4.5-stable", "con tag, se usa el tag")


func test_for_templates_skips_installed_platforms() -> void:
	var o := InstallOptions.for_templates(_installed("4.7.2-stable", "4.7.2-stable", false,
		PackedStringArray(["linux", "windows"])))
	assert_eq(o.platforms, PackedStringArray(["android", "ios", "macos", "visionos", "web"]))
	assert_eq(_line(o), "godot-manager --json templates 4.7.2-stable --platforms=android,ios,macos,visionos,web")
	o = InstallOptions.for_templates(_installed("x", "4.7.2-stable", false, GmCommands.PLATFORMS))
	assert_ne(o.problem(), "", "si ya tiene todas, no hay nada tildado")


func test_download_size() -> void:
	var r := RemoteVersion.new()
	r.editor_size = 60
	r.mono_size = 90
	r.templates_size = 1000
	var o := _opts()
	assert_eq(o.download_size(r), 60)
	o.mono = true
	assert_eq(o.download_size(r), 90)
	o.with_templates = true
	assert_eq(o.download_size(r), 1090)
	assert_eq(o.download_size(null), 0)
