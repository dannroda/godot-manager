extends Control
## Ventana principal: barra lateral con el logo y las secciones, y la pantalla
## activa a la derecha.
## Al arrancar carga los Ajustes, los pasa a GmCli y prueba el binario; si
## falla, muestra la franja de error y las pantallas no llaman al CLI
## (escuchan GmCli.availability_changed).

const MIN_WINDOW_SIZE := Vector2i(820, 480)
## Atajos que resuelve cada pantalla (acciones del Input Map).
const SCREEN_SHORTCUTS: Array[StringName] = [&"gm_search", &"gm_refresh", &"gm_delete"]

var settings: AppSettings

@onready var _screens: Array[Control] = [%ProjectsScreen, %InstalledScreen, %RemoteScreen]
@onready var _nav: Array[Button] = [%NavProjects, %NavInstalled, %NavRemote]
@onready var _banner: PanelContainer = %Banner
@onready var _banner_text: Label = %BannerText
@onready var _banner_retry: Button = %BannerRetry
@onready var _settings_dialog: ConfirmationDialog = $SettingsDialog
@onready var _output_panel: PanelContainer = %OutputPanel
@onready var _error_dialog: AcceptDialog = %ErrorDialog
@onready var _error_text: Label = %ErrorText


## Inglés salvo que el sistema esté en español. Va en _init, antes de que los
## hijos armen sus textos.
func _init() -> void:
	TranslationServer.set_locale(ui_locale(OS.get_locale_language()))


## Los textos fuente están en español; cualquier otro idioma ve el inglés.
static func ui_locale(os_language: String) -> String:
	return "es" if os_language == "es" else "en"


func _ready() -> void:
	_setup_window()
	for i in _nav.size():
		_nav[i].pressed.connect(_show_screen.bind(i))
	_show_screen(0)

	%Settings.pressed.connect(_open_settings)
	%BannerSettings.pressed.connect(_open_settings)
	_banner_retry.pressed.connect(_check_cli)
	_settings_dialog.update_banner = %UpdateBanner
	_settings_dialog.saved.connect(func(s: AppSettings) -> void:
		settings = s
		_check_cli())
	GmCli.availability_changed.connect(_on_availability_changed)
	GmCli.job_finished.connect(_on_job_finished)
	for screen: Control in [%RemoteScreen, %InstalledScreen, %ProjectsScreen]:
		screen.install_requested.connect(func(args: PackedStringArray, title: String) -> void:
			%JobPanel.run(args, title))
	%ProjectsScreen.error_reported.connect(show_cli_error)
	%ProjectsScreen.job_started.connect(func(job: CliJob, title: String) -> void:
		%JobPanel.track(job, title))
	%UpdateBanner.update_requested.connect(_run_update)
	%InstalledScreen.tab_requested.connect(func(tab: StringName) -> void:
		var target: Control = {&"projects": %ProjectsScreen, &"installed": %InstalledScreen,
			&"remote": %RemoteScreen}.get(tab)
		if target != null:
			_show_screen(_screens.find(target)))
	_error_dialog.add_button(tr("Ver salida"), true, "show_output")
	_error_dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"show_output":
			_error_dialog.hide()
			_output_panel.expand())

	settings = AppSettings.load_from()
	settings.apply_to(GmCli)
	_check_cli()


## Ctrl+Tab / Ctrl+Shift+Tab (también Ctrl+RePág/AvPág) cambian de sección.
## Va en _input porque si no la navegación de foco se come el Tab.
func _input(event: InputEvent) -> void:
	if _dialog_open() or not event is InputEventKey:
		return
	var step := 0
	if event.is_action_pressed(&"gm_next_tab", true, true):
		step = 1
	elif event.is_action_pressed(&"gm_prev_tab", true, true):
		step = -1
	if step != 0:
		_show_screen(posmod(current_screen() + step, _screens.size()))
		get_viewport().set_input_as_handled()


## Ctrl+F, F5 y Supr: los maneja la sección visible (`handle_shortcut`). En
## _unhandled_input, así un campo de texto con foco se queda con Supr.
func _unhandled_input(event: InputEvent) -> void:
	if _dialog_open() or not event is InputEventKey:
		return
	for action: StringName in SCREEN_SHORTCUTS:
		if event.is_action_pressed(action, false, true):
			var screen := _screens[current_screen()]
			if screen.has_method(&"handle_shortcut") and screen.handle_shortcut(action):
				get_viewport().set_input_as_handled()
			return


## Hay un diálogo abierto: los atajos no tocan la pantalla de atrás. Los
## diálogos son ventanas nativas (embed_subwindows=false), salvo en headless.
func _dialog_open() -> bool:
	for w: Node in find_children("*", "Window", true, false):
		if (w as Window).visible:
			return true
	return false


func current_screen() -> int:
	return _nav.find(_nav[0].button_group.get_pressed_button())


func _show_screen(index: int) -> void:
	# button_pressed suelta las otras del grupo (set_pressed_no_signal no) y no
	# emite `pressed`, así que no vuelve a entrar acá.
	_nav[index].button_pressed = true
	for i in _screens.size():
		_screens[i].visible = i == index
	# Al cambiar de sección con el teclado, el foco va a su lista (o búsqueda).
	var screen := _screens[index]
	if screen.has_method(&"focus_list"):
		screen.focus_list.call_deferred()


func _open_settings() -> void:
	_settings_dialog.open_with(settings)


func _check_cli() -> void:
	_banner_retry.disabled = true
	await GmCli.check()
	_banner_retry.disabled = false


## Aviso con el mensaje del CLI tal cual. Los jobs del chequeo de versión no
## avisan (ya los muestra la franja) y los que la pantalla maneja tampoco;
## `needs_confirmation` no es un error: lo pregunta el panel de progreso.
func _on_job_finished(job: CliJob) -> void:
	if not job.notify_on_error or job.args == GmCommands.cli_version():
		return
	var err := GmParse.job_error(job)
	if err == null or err.code == "needs_confirmation":
		return
	show_cli_error(err.message)


func show_cli_error(message: String) -> void:
	_error_text.text = message
	_error_dialog.popup_centered()


func _on_availability_changed(ok: bool, message: String) -> void:
	_banner.visible = not ok
	_banner_text.text = message
	if ok and not %UpdateBanner.updated:
		%UpdateBanner.check_if_due(settings)


## Actualiza godot-manager en el panel de progreso; al terminar, el CLI ya es
## otro: se vuelve a probar (versión nueva) y la franja ofrece reiniciar.
func _run_update(args: PackedStringArray, title: String) -> void:
	var job: CliJob = %JobPanel.run(args, title)
	if job == null:
		return
	if not job.is_done():
		await job.finished
	%UpdateBanner.on_update_finished(job)
	if job.succeeded():
		_check_cli()


## Escala la interfaz en pantallas HiDPI, como hace el Project Manager con su
## "auto" de escala, y fija el tamaño mínimo de la ventana.
func _setup_window() -> void:
	var window := get_window()
	var factor := ui_scale_for(DisplayServer.screen_get_scale(), DisplayServer.screen_get_dpi())
	window.content_scale_factor = factor
	# Los diálogos son ventanas nativas y no heredan la escala: se la pone cada una.
	for w: Node in find_children("*", "Window", true, false):
		(w as Window).content_scale_factor = factor
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is Window and n != window:
			(n as Window).content_scale_factor = factor)
	window.min_size = Vector2i(Vector2(MIN_WINDOW_SIZE) * factor)
	if factor > 1.0 and not window.mode in [Window.MODE_MAXIMIZED, Window.MODE_FULLSCREEN]:
		var screen := DisplayServer.window_get_current_screen()
		var usable := DisplayServer.screen_get_usable_rect(screen)
		var wanted := Vector2i(Vector2(window.size) * factor).min(usable.size)
		window.size = wanted
		window.position = usable.position + Vector2i(Vector2(usable.size - wanted) * 0.5)


## screen_get_scale() solo da algo distinto de 1 en macOS y Wayland; en X11 y
## Windows se mira el DPI, con los mismos cortes que el editor.
static func ui_scale_for(screen_scale: float, dpi: int) -> float:
	if screen_scale > 1.0:
		return screen_scale
	if dpi >= 192:
		return 2.0
	if dpi >= 144:
		return 1.5
	return 1.0
