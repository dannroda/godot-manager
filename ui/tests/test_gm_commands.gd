extends TestCase


func test_list_and_remote() -> void:
	assert_eq(GmCommands.list(), PackedStringArray(["--json", "list"]))
	assert_eq(GmCommands.list_remote(), PackedStringArray(["--json", "list-remote"]))
	assert_eq(GmCommands.list_remote("dev"), PackedStringArray(["--json", "list-remote", "dev"]))


func test_which_with_and_without_dir() -> void:
	assert_eq(GmCommands.which(), PackedStringArray(["--json", "which"]))
	assert_eq(GmCommands.which("/home/yo/Mis Juegos/p"),
		PackedStringArray(["--json", "--dir", "/home/yo/Mis Juegos/p", "which"]))


func test_install_plain() -> void:
	assert_eq(GmCommands.install("4.3-stable"), PackedStringArray(["--json", "install", "4.3-stable"]))


func test_install_all_options() -> void:
	assert_eq(GmCommands.install("4.8-beta3", true, true, true, ["linux", "windows"], true),
		PackedStringArray(["--json", "install", "4.8-beta3", "--mono", "--debugsymbols",
			"--templates", "--platforms=linux,windows", "--yes"]))


func test_install_templates_all_platforms() -> void:
	assert_eq(GmCommands.install("4.3-stable", false, false, true),
		PackedStringArray(["--json", "install", "4.3-stable", "--templates"]))


func test_templates() -> void:
	assert_eq(GmCommands.templates("4.3-stable"), PackedStringArray(["--json", "templates", "4.3-stable"]))
	assert_eq(GmCommands.templates("4.8-beta3", true, ["web"], true, false, true),
		PackedStringArray(["--json", "templates", "4.8-beta3", "--mono", "--platforms=web",
			"--debugsymbols", "--yes"]))
	assert_eq(GmCommands.templates("4.8-beta3", false, [], false, true),
		PackedStringArray(["--json", "templates", "4.8-beta3", "--debugsymbolsonly"]))


func test_symbols_set_remove_add() -> void:
	assert_eq(GmCommands.symbols("4.8-beta3"), PackedStringArray(["--json", "symbols", "4.8-beta3"]))
	assert_eq(GmCommands.set_default("4.3"), PackedStringArray(["--json", "set", "4.3"]))
	assert_eq(GmCommands.remove("4.3"), PackedStringArray(["--json", "remove", "4.3", "--yes"]))
	assert_eq(GmCommands.remove("4.3", true),
		PackedStringArray(["--json", "remove", "4.3", "--yes", "--templates"]))
	assert_eq(GmCommands.add("mi build", "/opt/x y/godot"),
		PackedStringArray(["--json", "add", "mi build", "/opt/x y/godot"]))
	assert_eq(GmCommands.add("b", "/p", true), PackedStringArray(["--json", "add", "b", "/p", "--symlink"]))
	assert_eq(GmCommands.add("b", "/p", false, true), PackedStringArray(["--json", "add", "b", "/p", "--force"]))


func test_set_local_and_unset() -> void:
	assert_eq(GmCommands.set_local("C:/Juegos/Mi \"juego\"", "4.3"),
		PackedStringArray(["--json", "--dir", "C:/Juegos/Mi \"juego\"", "set-local", "4.3"]))
	assert_eq(GmCommands.unset_local("/p"), PackedStringArray(["--json", "--dir", "/p", "set-local", "--unset"]))


func test_launch_and_open_project() -> void:
	assert_eq(GmCommands.launch("4.3"), PackedStringArray(["--json", "launch", "--detach", "4.3"]))
	assert_eq(GmCommands.launch("4.3", ["-p"]), PackedStringArray(["--json", "launch", "--detach", "4.3", "-p"]))
	assert_eq(GmCommands.open_project("/home/yo/a b"),
		PackedStringArray(["--json", "--dir", "/home/yo/a b", "run", "--detach", "-e"]))


func test_plugins() -> void:
	var d := "/home/yo/Mis Juegos/p"
	assert_eq(GmCommands.plugins(d), PackedStringArray(["--json", "--dir", d, "plugins"]))
	assert_eq(GmCommands.plugin_enable(d, "a/b", true), PackedStringArray(["--json", "--dir", d, "plugins", "enable", "a/b"]))
	assert_eq(GmCommands.plugin_enable(d, "x", false), PackedStringArray(["--json", "--dir", d, "plugins", "disable", "x"]))
	assert_eq(GmCommands.plugin_remove(d, "x"), PackedStringArray(["--json", "--dir", d, "plugins", "remove", "x", "--yes"]))


func test_outdated_and_upgrade() -> void:
	assert_eq(GmCommands.outdated(), PackedStringArray(["--json", "outdated"]))
	assert_eq(GmCommands.upgrade("4.5-stable-mono"), PackedStringArray(["--json", "upgrade", "4.5-stable-mono"]))


func test_prune_passes_projects() -> void:
	var projects := PackedStringArray(["/home/yo/Mis Juegos/a", "C:/b"])
	assert_eq(GmCommands.prune(projects, true),
		PackedStringArray(["--json", "prune", "--dry-run", "/home/yo/Mis Juegos/a", "C:/b"]))
	assert_eq(GmCommands.prune([], false), PackedStringArray(["--json", "prune", "--yes"]))


func test_path() -> void:
	assert_eq(GmCommands.path_status(), PackedStringArray(["--json", "path"]))
	assert_eq(GmCommands.path_change(true), PackedStringArray(["--json", "path", "add"]))
	assert_eq(GmCommands.path_change(false), PackedStringArray(["--json", "path", "remove"]))


func test_plugin_store_commands() -> void:
	var d := "/home/yo/Mis Juegos/p"
	var base := PackedStringArray(["--json", "--dir", d, "plugins"])
	assert_eq(GmCommands.plugin_search(d, "dialogue manager", 2), base + PackedStringArray(["search", "dialogue manager", "--page", "2"]))
	assert_eq(GmCommands.plugin_search(d, " ", 1), base + PackedStringArray(["search", "--page", "1"]), "sin texto: los populares")
	assert_eq(GmCommands.plugin_add(d, "github:a/b@v1"), base + PackedStringArray(["add", "github:a/b@v1"]))
	assert_eq(GmCommands.plugin_add(d, "a/b", true), base + PackedStringArray(["add", "a/b", "--pin"]))
	assert_eq(GmCommands.plugin_install(d), base + PackedStringArray(["install"]))
	assert_eq(GmCommands.plugin_outdated(d), base + PackedStringArray(["outdated"]))
	assert_eq(GmCommands.plugin_update(d), base + PackedStringArray(["update"]))
	assert_eq(GmCommands.plugin_update(d, ["x", "y"]), base + PackedStringArray(["update", "x", "y"]))
	assert_eq(GmCommands.plugin_pin(d, "x"), base + PackedStringArray(["pin", "x"]))
	assert_eq(GmCommands.plugin_unpin(d, "x"), base + PackedStringArray(["unpin", "x"]))
	assert_eq(GmCommands.plugin_apply(d, "mios"), base + PackedStringArray(["apply", "mios"]))


func test_presets_and_new() -> void:
	assert_eq(GmCommands.presets(), PackedStringArray(["--json", "presets"]))
	assert_eq(GmCommands.preset_save("/p", "mios", true),
		PackedStringArray(["--json", "--dir", "/p", "presets", "save", "mios", "--force", "--pin"]))
	assert_eq(GmCommands.preset_remove("mios"), PackedStringArray(["--json", "presets", "remove", "mios"]))
	assert_eq(GmCommands.new_project("/j/Mi juego", "Mi juego"),
		PackedStringArray(["--json", "new", "/j/Mi juego", "--name", "Mi juego", "--renderer", "forward_plus"]))
	assert_eq(GmCommands.new_project("/j/x", "x", "4.5-stable", "mobile", "mios"),
		PackedStringArray(["--json", "new", "/j/x", "--name", "x", "--renderer", "mobile", "--version", "4.5-stable", "--preset", "mios"]))
