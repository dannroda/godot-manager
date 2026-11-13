extends TestCase
## GmCli y CliJob. Los tests de mecánica (paralelo, cola, cancelar, líneas)
## usan /bin/sh en vez del CLI, así se controla el tiempo; los de contrato
## usan el CLI real (GM_BIN).

const GmCliScript := preload("res://cli/gm_cli.gd")

var cli: Node


func before_each() -> void:
	cli = GmCliScript.new()
	tree.root.add_child(cli)


func after_each() -> void:
	for job: CliJob in cli.history:
		if not job.is_done():
			cli.cancel(job)
	cli.queue_free()
	await wait_frames(1)


func _sh(script: String) -> PackedStringArray:
	return ["-c", script]


func _needs_sh() -> bool:
	if OS.get_name() == "Windows":
		skip("usa /bin/sh")
		return false
	cli.binary = "/bin/sh"
	return true


func _needs_cli() -> bool:
	var bin := OS.get_environment("GM_BIN")
	if bin.is_empty():
		skip("falta GM_BIN (ruta a godot-manager)")
		return false
	cli.binary = bin
	return true


func test_lines_and_streams() -> void:
	if not _needs_sh():
		return
	var lines: Array = []
	var job: CliJob = cli.read(_sh("echo uno; echo dos >&2; printf 'tres'; exit 3"))
	job.line_received.connect(func(s: CliJob.Stream, t: String) -> void: lines.append([s, t]))
	await job.finished
	assert_eq(job.exit_code, 3)
	assert_eq(job.stdout, "uno\ntres\n")
	assert_eq(job.stderr, "dos\n")
	assert_has(lines, [CliJob.Stream.STDOUT, "uno"])
	assert_has(lines, [CliJob.Stream.STDERR, "dos"])
	assert_has(lines, [CliJob.Stream.STDOUT, "tres"], "la última línea sin \\n también llega")
	assert_false(job.succeeded())


func test_partial_lines_arrive_while_running() -> void:
	if not _needs_sh():
		return
	var job: CliJob = cli.read(_sh("echo primera; sleep 0.5; echo segunda"))
	var first_at := [0]
	job.line_received.connect(func(_s: CliJob.Stream, t: String) -> void:
		if t == "primera":
			first_at[0] = Time.get_ticks_msec())
	await job.finished
	assert_true(first_at[0] > 0)
	assert_true(job.ended_msec - first_at[0] >= 300, "la primera línea llegó antes de que termine")


func test_does_not_block_frames() -> void:
	if not _needs_sh():
		return
	var job: CliJob = cli.read(_sh("sleep 0.6"))
	var frames := 0
	var longest := 0
	var last := Time.get_ticks_msec()
	while not job.is_done():
		await tree.process_frame
		var now := Time.get_ticks_msec()
		longest = maxi(longest, now - last)
		last = now
		frames += 1
	assert_true(frames > 5, "pasaron %d cuadros mientras corría" % frames)
	assert_true(longest < 200, "cuadro más largo: %d ms" % longest)


func test_reads_run_in_parallel() -> void:
	if not _needs_sh():
		return
	var a: CliJob = cli.read(_sh("sleep 0.4; echo a"))
	var b: CliJob = cli.read(_sh("sleep 0.4; echo b"))
	var t0 := Time.get_ticks_msec()
	await wait_until(func() -> bool: return a.is_done() and b.is_done())
	assert_true(Time.get_ticks_msec() - t0 < 750, "las dos lecturas corrieron a la vez")
	assert_eq(a.stdout, "a\n")
	assert_eq(b.stdout, "b\n")


func test_writes_run_one_at_a_time() -> void:
	if not _needs_sh():
		return
	var a: CliJob = cli.write(_sh("sleep 0.3; echo a"))
	var b: CliJob = cli.write(_sh("echo b"))
	assert_eq(b.state, CliJob.State.QUEUED)
	await wait_until(func() -> bool: return b.is_done())
	assert_true(b.started_msec >= a.ended_msec, "b arrancó después de que terminó a")
	assert_eq(b.stdout, "b\n")


func test_read_does_not_wait_for_writes() -> void:
	if not _needs_sh():
		return
	var w: CliJob = cli.write(_sh("sleep 0.5"))
	var r: CliJob = cli.read(_sh("echo ya"))
	await r.finished
	assert_false(w.is_done(), "la lectura terminó mientras la escritura seguía")


func test_cancel_running() -> void:
	if not _needs_sh():
		return
	var job: CliJob = cli.read(_sh("sleep 10"))
	await wait_frames(2)
	var pid := job.pid
	var t0 := Time.get_ticks_msec()
	cli.cancel(job)
	assert_true(job.is_done(), "cancelar cierra el job enseguida")
	assert_true(job.cancelled)
	assert_false(job.succeeded())
	assert_true(Time.get_ticks_msec() - t0 < 1000)
	if OS.get_name() != "Windows":
		var out: Array = []
		OS.execute("/bin/sh", ["-c", "kill -0 %d 2>/dev/null && echo vivo || echo muerto" % pid], out)
		assert_eq("".join(out).strip_edges(), "muerto", "el proceso ya no existe")


func test_cancel_running_write_starts_next() -> void:
	if not _needs_sh():
		return
	var a: CliJob = cli.write(_sh("sleep 10"))
	var b: CliJob = cli.write(_sh("echo b"))
	await wait_frames(2)
	cli.cancel(a)
	await wait_until(func() -> bool: return b.is_done(), 3.0)
	assert_eq(b.stdout, "b\n")


func test_cancel_queued_write() -> void:
	if not _needs_sh():
		return
	var a: CliJob = cli.write(_sh("sleep 0.3"))
	var b: CliJob = cli.write(_sh("echo nunca"))
	cli.cancel(b)
	assert_true(b.is_done())
	await wait_until(func() -> bool: return a.is_done())
	await wait_frames(2)
	assert_eq(b.stdout, "", "b no llegó a correr")


func test_history_and_signals() -> void:
	if not _needs_sh():
		return
	var finished: Array = []
	cli.job_finished.connect(func(j: CliJob) -> void: finished.append(j))
	var job: CliJob = cli.read(_sh("true"))
	await job.finished
	await wait_frames(1)
	assert_has(cli.history, job)
	assert_has(finished, job)


func test_missing_binary() -> void:
	cli.binary = "/no/existe/godot-manager"
	var job: CliJob = cli.read(GmCommands.list())
	await wait_until(func() -> bool: return job.is_done(), 1.0)
	assert_true(job.is_done())
	assert_eq(job.start_error.code, CliError.NO_BINARY)
	assert_false(job.succeeded())


func test_resolve_binary_in_path() -> void:
	if OS.get_name() == "Windows":
		skip("usa sh")
		return
	assert_eq(GmCliScript.resolve_binary("sh").get_file(), "sh")
	assert_eq(GmCliScript.resolve_binary("no-existe-esto-123"), "")
	assert_eq(GmCliScript.resolve_binary("/bin/sh"), "/bin/sh")


## 4.3: PATH de Windows (con `;` y entradas entre comillas) y de Linux.
func test_path_dirs() -> void:
	assert_eq(GmCliScript.path_dirs("C:\\Windows;\"C:\\Program Files\\gm\";;C:\\x ", true),
		PackedStringArray(["C:\\Windows", "C:\\Program Files\\gm", "C:\\x"]))
	assert_eq(GmCliScript.path_dirs("/usr/bin::/opt/a b", false), PackedStringArray(["/usr/bin", "/opt/a b"]))


## 4.3: el comando que se ve en Salida y copia Copiar, pegable en cada shell.
func test_format_command_quoting() -> void:
	var args := PackedStringArray(["--dir", "C:\\Mis Juegos\\uno", "run"])
	assert_eq(CliJob.format_command(args, "godot-manager.exe", true),
		"godot-manager.exe --dir \"C:\\Mis Juegos\\uno\" run")
	assert_eq(CliJob.format_command(PackedStringArray(["--dir", "/a b/it's"]), "godot-manager", false),
		"godot-manager --dir '/a b/it'\\''s'")


func test_cli_version() -> void:
	if not _needs_cli():
		return
	var job: CliJob = cli.read(GmCommands.cli_version())
	await job.finished
	assert_eq(job.exit_code, 0)
	assert_true(job.stdout.strip_edges().length() > 0, "imprime la versión")


func test_cli_unknown_command() -> void:
	if not _needs_cli():
		return
	var plain: CliJob = cli.read(["bogus"])
	await plain.finished
	assert_eq(plain.exit_code, 1)
	assert_has(plain.stderr, "bogus", "sin --json el error va a stderr")
	var json: CliJob = cli.read(["--json", "bogus"])
	await json.finished
	assert_eq(json.exit_code, 1)
	assert_eq(GmParse.parse_ok(json.stdout).error.code, "unknown_command")


func test_cli_env_godot_dir() -> void:
	if not _needs_cli():
		return
	var fx := CliFixture.new()
	if not assert_true(fx.setup(["9.1-fake"]), fx.last_error):
		fx.teardown()
		return
	var root := fx.root
	fx.teardown()  # Saca GODOT_DIR del entorno: tiene que llegar por GmCli.env.
	DirAccess.make_dir_recursive_absolute(root)
	fx.root = root
	fx.gm_bin = cli.binary
	OS.set_environment("GODOT_DIR", root)
	fx.run(GmCommands.add("9.1-fake", CliFixture.fake_executable()))
	OS.unset_environment("GODOT_DIR")

	cli.env = {"GODOT_DIR": root}
	var job: CliJob = cli.read(GmCommands.list())
	await job.finished
	var r := GmParse.parse_list(job.stdout)
	if assert_true(r.ok, str(r.error)):
		assert_eq((r.value as Array).size(), 1)
	cli.env = {}
	var job2: CliJob = cli.read(GmCommands.list())
	await job2.finished
	assert_false(OS.has_environment("GODOT_DIR"), "al vaciar el ajuste se restaura el entorno")
	CliFixture._remove_tree(root)
