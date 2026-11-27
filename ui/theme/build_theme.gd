extends SceneTree
## Genera res://theme/app_theme.tres: el tema por defecto de Godot 4.8 más las
## variaciones propias de la app (filas, títulos, el botón de acento...).
## Uso: godot --headless --path . --script res://theme/build_theme.gd
## Los tipos base (Button, LineEdit, TabBar...) no se tocan: quedan como los
## trae el motor. Las variaciones propias usan la paleta de abajo; el acento es
## el azul del logo (icon.svg).

const OUT := "res://theme/app_theme.tres"

const RADIUS := 3
const BG := Color("#15171b")
const SIDEBAR := Color("#1b1e23")
const LINE := Color("#272b31")
const NAV_ACTIVE := Color("#262b33")
const TEXT := Color("#e8eaed")
const TEXT_DIM := Color("#b8bec7")
const ACCENT := Color("#70bafa")
const ON_ACCENT := Color("#0f1a24")


func _init() -> void:
	var t := Theme.new()

	_variant(t, "DimLabel", "Label")
	t.set_color("font_color", "DimLabel", Color(1, 1, 1, 0.6))
	_variant(t, "TitleLabel", "Label")
	t.set_font_size("font_size", "TitleLabel", 18)

	_variant(t, "SectionTitle", "Label")
	t.set_font_size("font_size", "SectionTitle", 17)
	t.set_color("font_color", "SectionTitle", Color(1, 1, 1, 1))

	_variant(t, "AccentButton", "Button")
	t.set_stylebox("normal", "AccentButton", _box(ACCENT, RADIUS + 3, 12, 6))
	t.set_stylebox("hover", "AccentButton", _box(ACCENT.lightened(0.15), RADIUS + 3, 12, 6))
	t.set_stylebox("pressed", "AccentButton", _box(ACCENT.darkened(0.15), RADIUS + 3, 12, 6))
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
			"font_hover_pressed_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		t.set_color(c, "AccentButton", ON_ACCENT)

	_variant(t, "AppBackground", "Panel")
	t.set_stylebox("panel", "AppBackground", _box(BG, 0))
	_variant(t, "Sidebar", "PanelContainer")
	var side := _box(SIDEBAR, 0, 12, 18)
	side.border_width_right = 1
	side.border_color = LINE
	t.set_stylebox("panel", "Sidebar", side)
	_variant(t, "BrandLabel", "Label")
	t.set_font_size("font_size", "BrandLabel", 16)
	t.set_color("font_color", "BrandLabel", TEXT)

	# Entradas de la barra lateral: planas, la activa (pressed) con fondo.
	_variant(t, "NavButton", "Button")
	t.set_stylebox("normal", "NavButton", _box(Color.TRANSPARENT, RADIUS + 5, 10, 9))
	t.set_stylebox("hover", "NavButton", _box(Color(1, 1, 1, 0.05), RADIUS + 5, 10, 9))
	t.set_stylebox("pressed", "NavButton", _box(NAV_ACTIVE, RADIUS + 5, 10, 9))
	t.set_stylebox("hover_pressed", "NavButton", _box(NAV_ACTIVE, RADIUS + 5, 10, 9))
	var nav_focus := _box(Color.TRANSPARENT, RADIUS + 5)
	nav_focus.draw_center = false
	nav_focus.set_border_width_all(1)
	nav_focus.border_color = ACCENT
	t.set_stylebox("focus", "NavButton", nav_focus)
	t.set_constant("h_separation", "NavButton", 10)
	for c: String in ["font_color", "icon_normal_color"]:
		t.set_color(c, "NavButton", TEXT_DIM)
	for c: String in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color",
			"font_focus_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color",
			"icon_focus_color"]:
		t.set_color(c, "NavButton", Color.WHITE)

	_variant(t, "TopBar", "PanelContainer")
	var top := StyleBoxEmpty.new()
	top.content_margin_left = 12
	top.content_margin_right = 12
	top.content_margin_top = 6
	top.content_margin_bottom = 6
	t.set_stylebox("panel", "TopBar", top)
	_variant(t, "ScreenPanel", "PanelContainer")
	t.set_stylebox("panel", "ScreenPanel", _box(Color(0.1, 0.1, 0.1, 0.6), RADIUS, 12, 12))
	_variant(t, "ListPanel", "PanelContainer")
	t.set_stylebox("panel", "ListPanel", _box(Color(0, 0, 0, 0.25), RADIUS, 6, 6))
	_variant(t, "RowPanel", "PanelContainer")
	t.set_stylebox("panel", "RowPanel", _box(Color.TRANSPARENT, RADIUS, 12, 8))
	_variant(t, "RowPanelHover", "PanelContainer")
	t.set_stylebox("panel", "RowPanelHover", _box(Color(1, 1, 1, 0.05), RADIUS, 12, 8))
	_variant(t, "RowPanelSelected", "PanelContainer")
	var sel := _box(Color(1, 1, 1, 0.12), RADIUS, 12, 8)
	sel.border_width_left = 2
	sel.border_color = Color(1, 1, 1, 0.6)
	t.set_stylebox("panel", "RowPanelSelected", sel)
	_variant(t, "SettingsSection", "PanelContainer")
	t.set_stylebox("panel", "SettingsSection", _box(Color(1, 1, 1, 0.04), RADIUS + 1, 14, 12))
	_variant(t, "ErrorBanner", "PanelContainer")
	var banner := _box(Color("#4a2328"), 0, 12, 8)
	banner.border_width_bottom = 1
	banner.border_color = Color("#a8474f")
	t.set_stylebox("panel", "ErrorBanner", banner)
	_variant(t, "Tag", "PanelContainer")
	t.set_stylebox("panel", "Tag", _box(Color(1, 1, 1, 0.1), RADIUS, 6, 1))

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://theme"))
	var err := ResourceSaver.save(t, OUT)
	if err != OK:
		push_error("No se pudo guardar %s: %s" % [OUT, error_string(err)])
		quit(1)
		return
	print("Tema guardado en ", OUT)
	quit(0)


func _variant(t: Theme, name: StringName, base: StringName) -> void:
	t.set_type_variation(name, base)


func _box(color: Color, radius: int = RADIUS, margin_h: int = -1, margin_v: int = -1) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = color
	b.set_corner_radius_all(radius)
	if margin_h >= 0:
		b.content_margin_left = margin_h
		b.content_margin_right = margin_h
	if margin_v >= 0:
		b.content_margin_top = margin_v
		b.content_margin_bottom = margin_v
	return b
