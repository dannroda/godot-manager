extends SceneTree
## Genera res://theme/app_theme.tres: el tema por defecto de Godot 4.8 más las
## variaciones propias de la app (filas, títulos, el botón de acento...).
## Uso: godot --headless --path . --script res://theme/build_theme.gd
## Los tipos base (Button, LineEdit, TabBar...) no se tocan: quedan como los
## trae el motor. Las variaciones usan los mismos grises semitransparentes.

const OUT := "res://theme/app_theme.tres"

const RADIUS := 3


func _init() -> void:
	var t := Theme.new()

	_variant(t, "DimLabel", "Label")
	t.set_color("font_color", "DimLabel", Color(1, 1, 1, 0.6))
	_variant(t, "TitleLabel", "Label")
	t.set_font_size("font_size", "TitleLabel", 18)

	_variant(t, "AccentButton", "Button")
	t.set_stylebox("normal", "AccentButton", _box(Color(1, 1, 1, 0.2), RADIUS, 10, 5))
	t.set_stylebox("hover", "AccentButton", _box(Color(1, 1, 1, 0.3), RADIUS, 10, 5))
	t.set_stylebox("pressed", "AccentButton", _box(Color(1, 1, 1, 0.1), RADIUS, 10, 5))

	_variant(t, "TopBar", "PanelContainer")
	var top := StyleBoxEmpty.new()
	top.content_margin_left = 8
	top.content_margin_right = 8
	t.set_stylebox("panel", "TopBar", top)
	_variant(t, "ScreenPanel", "PanelContainer")
	t.set_stylebox("panel", "ScreenPanel", _box(Color(0.1, 0.1, 0.1, 0.6), RADIUS, 10, 10))
	_variant(t, "ListPanel", "PanelContainer")
	t.set_stylebox("panel", "ListPanel", _box(Color(0, 0, 0, 0.25), RADIUS, 4, 4))
	_variant(t, "RowPanel", "PanelContainer")
	t.set_stylebox("panel", "RowPanel", _box(Color.TRANSPARENT, RADIUS, 10, 6))
	_variant(t, "RowPanelHover", "PanelContainer")
	t.set_stylebox("panel", "RowPanelHover", _box(Color(1, 1, 1, 0.05), RADIUS, 10, 6))
	_variant(t, "RowPanelSelected", "PanelContainer")
	var sel := _box(Color(1, 1, 1, 0.12), RADIUS, 10, 6)
	sel.border_width_left = 2
	sel.border_color = Color(1, 1, 1, 0.6)
	t.set_stylebox("panel", "RowPanelSelected", sel)
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
