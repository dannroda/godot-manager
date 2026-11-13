extends SceneTree
## Genera res://theme/editor_dark.tres, el tema oscuro que imita al editor 4.x.
## Uso: godot --headless --path . --script res://theme/build_theme.gd
## Los colores salen del tema oscuro por defecto del editor (base #363d4a, acento #70bafa).

const OUT := "res://theme/editor_dark.tres"

const ACCENT := Color("#70bafa")
const BG := Color("#1d2229")          # fondo de la ventana y barra de pestañas
const PANEL := Color("#21262e")       # panel de cada pantalla
const SURFACE := Color("#282e38")     # paneles internos, diálogos, pestaña activa
const BUTTON := Color("#323946")
const BUTTON_HOVER := Color("#3d4555")
const BUTTON_PRESSED := Color("#1b1f26")
const BUTTON_DISABLED := Color("#2a2f38")
const FIELD := Color("#1a1e24")
const BORDER := Color("#3d4555")
const FONT := Color("#cdcfd2")
const FONT_BRIGHT := Color("#e0e2e5")
const FONT_DIM := Color("#8b919b")
const FONT_DISABLED := Color("#6b717b")
const RADIUS := 3


func _init() -> void:
	var t := Theme.new()
	t.default_font_size = 14

	t.set_stylebox("panel", "Panel", _box(PANEL, 0))
	t.set_stylebox("panel", "PanelContainer", _box(SURFACE))

	t.set_color("font_color", "Label", FONT)
	_variant(t, "DimLabel", "Label")
	t.set_color("font_color", "DimLabel", FONT_DIM)
	_variant(t, "TitleLabel", "Label")
	t.set_color("font_color", "TitleLabel", FONT_BRIGHT)
	t.set_font_size("font_size", "TitleLabel", 16)

	_buttons(t, "Button")
	_buttons(t, "OptionButton")
	_buttons(t, "MenuButton")
	_variant(t, "AccentButton", "Button")
	t.set_stylebox("normal", "AccentButton", _box(ACCENT.darkened(0.35), RADIUS, 10, 5))
	t.set_stylebox("hover", "AccentButton", _box(ACCENT.darkened(0.2), RADIUS, 10, 5))
	t.set_color("font_color", "AccentButton", Color.WHITE)

	for cls: String in ["CheckBox", "CheckButton"]:
		t.set_color("font_color", cls, FONT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, FONT)
		t.set_color("font_hover_pressed_color", cls, Color.WHITE)
		t.set_color("font_disabled_color", cls, FONT_DISABLED)
		t.set_stylebox("focus", cls, _focus())
		var flat := _box(Color.TRANSPARENT, RADIUS, 4, 4)
		for state: String in ["normal", "pressed", "disabled", "hover_pressed"]:
			t.set_stylebox(state, cls, flat)
		t.set_stylebox("hover", cls, _box(Color(1, 1, 1, 0.05), RADIUS, 4, 4))

	t.set_color("font_color", "LineEdit", FONT_BRIGHT)
	t.set_color("font_placeholder_color", "LineEdit", Color("#7a808a"))
	t.set_color("caret_color", "LineEdit", FONT_BRIGHT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))
	var field := _box(FIELD, RADIUS, 8, 5)
	field.border_width_bottom = 1
	field.border_color = BORDER
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", _focus())
	t.set_stylebox("read_only", "LineEdit", _box(Color("#23272e"), RADIUS, 8, 5))

	t.set_color("font_selected_color", "TabBar", Color.WHITE)
	t.set_color("font_unselected_color", "TabBar", Color("#9aa0a9"))
	t.set_color("font_hovered_color", "TabBar", FONT_BRIGHT)
	t.set_color("font_disabled_color", "TabBar", FONT_DISABLED)
	var tab_sel := _box(PANEL, 0, 16, 6)
	tab_sel.border_width_top = 2
	tab_sel.border_color = ACCENT
	t.set_stylebox("tab_selected", "TabBar", tab_sel)
	t.set_stylebox("tab_unselected", "TabBar", _box(BG, 0, 16, 6))
	t.set_stylebox("tab_hovered", "TabBar", _box(Color("#2b313c"), 0, 16, 6))
	t.set_stylebox("tab_focus", "TabBar", _focus())
	t.set_constant("h_separation", "TabBar", 4)

	for cls: String in ["VScrollBar", "HScrollBar"]:
		var scroll := StyleBoxEmpty.new()
		scroll.set_content_margin_all(3)
		t.set_stylebox("scroll", cls, scroll)
		t.set_stylebox("scroll_focus", cls, scroll)
		t.set_stylebox("grabber", cls, _box(Color("#4a5262"), 4, 3, 3))
		t.set_stylebox("grabber_highlight", cls, _box(Color("#5d6678"), 4, 3, 3))
		t.set_stylebox("grabber_pressed", cls, _box(ACCENT, 4, 3, 3))

	var popup := _box(PANEL, RADIUS, 4, 4)
	_border(popup, 1, BORDER)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", _box(Color(ACCENT, 0.2)))
	t.set_color("font_color", "PopupMenu", FONT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_disabled_color", "PopupMenu", FONT_DISABLED)
	t.set_color("font_separator_color", "PopupMenu", FONT_DIM)

	t.set_stylebox("panel", "AcceptDialog", _box(SURFACE, 0, 12, 12))
	t.set_stylebox("embedded_border", "Window", _window_border())
	t.set_stylebox("embedded_unfocused_border", "Window", _window_border())
	t.set_color("title_color", "Window", FONT_BRIGHT)

	var tooltip := _box(FIELD, RADIUS, 8, 4)
	_border(tooltip, 1, BORDER)
	t.set_stylebox("panel", "TooltipPanel", tooltip)
	t.set_color("font_color", "TooltipLabel", FONT_BRIGHT)

	t.set_stylebox("background", "ProgressBar", _box(FIELD))
	t.set_stylebox("fill", "ProgressBar", _box(ACCENT))
	t.set_color("font_color", "ProgressBar", FONT_BRIGHT)

	t.set_color("default_color", "RichTextLabel", FONT)
	t.set_stylebox("normal", "RichTextLabel", _box(FIELD, RADIUS, 8, 6))
	t.set_stylebox("focus", "RichTextLabel", StyleBoxEmpty.new())

	var sep := StyleBoxLine.new()
	sep.color = BORDER
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 8)
	var vsep := StyleBoxLine.new()
	vsep.color = BORDER
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)
	t.set_constant("separation", "VBoxContainer", 6)
	t.set_constant("separation", "HBoxContainer", 6)

	# Variaciones propias de la app.
	_variant(t, "TopBar", "PanelContainer")
	t.set_stylebox("panel", "TopBar", _box(BG, 0, 8, 0))
	_variant(t, "ScreenPanel", "PanelContainer")
	t.set_stylebox("panel", "ScreenPanel", _box(PANEL, 0, 10, 10))
	_variant(t, "ListPanel", "PanelContainer")
	var list := _box(BG, RADIUS, 4, 4)
	_border(list, 1, Color("#2b313c"))
	t.set_stylebox("panel", "ListPanel", list)
	_variant(t, "RowPanel", "PanelContainer")
	t.set_stylebox("panel", "RowPanel", _box(Color.TRANSPARENT, RADIUS, 10, 6))
	_variant(t, "RowPanelHover", "PanelContainer")
	t.set_stylebox("panel", "RowPanelHover", _box(Color(1, 1, 1, 0.05), RADIUS, 10, 6))
	_variant(t, "RowPanelSelected", "PanelContainer")
	var sel := _box(Color(ACCENT, 0.18), RADIUS, 10, 6)
	sel.border_width_left = 2
	sel.border_color = ACCENT
	t.set_stylebox("panel", "RowPanelSelected", sel)
	_variant(t, "ErrorBanner", "PanelContainer")
	var banner := _box(Color("#4a2328"), 0, 12, 8)
	banner.border_width_bottom = 1
	banner.border_color = Color("#a8474f")
	t.set_stylebox("panel", "ErrorBanner", banner)
	_variant(t, "Tag", "PanelContainer")
	t.set_stylebox("panel", "Tag", _box(Color("#3a4252"), RADIUS, 6, 1))

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://theme"))
	var err := ResourceSaver.save(t, OUT)
	if err != OK:
		push_error("No se pudo guardar %s: %s" % [OUT, error_string(err)])
		quit(1)
		return
	print("Tema guardado en ", OUT)
	quit(0)


func _buttons(t: Theme, cls: String) -> void:
	t.set_color("font_color", cls, FONT)
	t.set_color("font_hover_color", cls, Color.WHITE)
	t.set_color("font_pressed_color", cls, ACCENT)
	t.set_color("font_hover_pressed_color", cls, ACCENT.lightened(0.3))
	t.set_color("font_focus_color", cls, Color.WHITE)
	t.set_color("font_disabled_color", cls, FONT_DISABLED)
	t.set_color("icon_normal_color", cls, FONT)
	t.set_color("icon_disabled_color", cls, FONT_DISABLED)
	t.set_stylebox("normal", cls, _box(BUTTON, RADIUS, 10, 5))
	t.set_stylebox("hover", cls, _box(BUTTON_HOVER, RADIUS, 10, 5))
	t.set_stylebox("pressed", cls, _box(BUTTON_PRESSED, RADIUS, 10, 5))
	t.set_stylebox("hover_pressed", cls, _box(BUTTON_PRESSED, RADIUS, 10, 5))
	t.set_stylebox("disabled", cls, _box(BUTTON_DISABLED, RADIUS, 10, 5))
	t.set_stylebox("focus", cls, _focus())


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


func _border(b: StyleBoxFlat, width: int, color: Color) -> void:
	b.set_border_width_all(width)
	b.border_color = color


func _focus() -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.draw_center = false
	b.set_corner_radius_all(RADIUS)
	_border(b, 2, ACCENT)
	return b


func _window_border() -> StyleBoxFlat:
	var b := _box(SURFACE, RADIUS)
	_border(b, 1, BORDER)
	b.expand_margin_left = 6
	b.expand_margin_right = 6
	b.expand_margin_bottom = 6
	b.expand_margin_top = 28
	return b
