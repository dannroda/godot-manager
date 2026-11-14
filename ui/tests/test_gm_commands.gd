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
