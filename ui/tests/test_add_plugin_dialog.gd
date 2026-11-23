extends TestCase
## Agregar plugin: sugeridos (los nuestros primero), tarjetas con qué es cada
## uno (plugin o recursos), miniaturas y la fuente a mano. Sin red: el CLI no
## está disponible y las miniaturas no bajan.

const DIALOG := preload("res://dialogs/add_plugin_dialog.tscn")

var dialog: AcceptDialog
var _old_available := false


func before_each() -> void:
	_old_available = GmCli.available
	GmCli.available = false
	dialog = DIALOG.instantiate()
	tree.root.add_child(dialog)
	dialog.thumbnails.enabled = false


func after_each() -> void:
	GmCli.available = _old_available
	dialog.queue_free()
	await wait_frames(1)


func _asset(name: String, kind: StoreAsset.Kind, tags: PackedStringArray = []) -> StoreAsset:
	var a := StoreAsset.new()
	a.source = "store:pub/" + name.to_lower().replace(" ", "-")
	a.name = name
	a.publisher = "Pub"
	a.description = "Hace cosas"
	a.license = "MIT"
	a.score = 81
	a.kind = kind
	a.tags = tags
	a.page_url = "https://store.godotengine.org/asset/pub/x/"
	return a


func _cards() -> Array[Node]:
	return dialog.get_node("%Results").get_children()


func _text(card: Node, name: String) -> String:
	var node := card.find_child(name, true, false)
	if node is Label:
		return (node as Label).text
	if node != null:
		var label := node.find_child("*", true, false) as Label
		return label.text if label != null else ""
	return ""


func test_open_shows_ours_as_suggested() -> void:
	dialog.open_for("/p")
	var cards := _cards()
	assert_eq(cards.size(), 2, "sin CLI, solo los nuestros")
	assert_eq(_text(cards[0], "Title"), "Godot Agent")
	assert_true(cards[0].get_meta(&"featured"))
	assert_eq(_text(cards[0], "Featured"), "Sugerido")
	assert_eq(_text(cards[0], "Kind"), "Plugin")
	assert_has(_text(cards[0], "Meta"), "GitHub")
	assert_eq((cards[0].find_child("View", true, false) as Button).text, "Ver en GitHub")
	assert_has((dialog.get_node("%SearchStatus") as Label).text, "solo se muestran los nuestros")
	assert_true(dialog.get_node_or_null("Content/FeaturedLabel") == null, "ya no hay una barra aparte para los nuestros")
	dialog.hide()


func test_featured_filter() -> void:
	assert_eq(dialog.featured().size(), 2)
	assert_eq(dialog.featured("compass").size(), 1)
	assert_eq(dialog.featured("MCP")[0].name, "Godot Agent", "también por etiqueta")
	assert_true(dialog.featured("terrain").is_empty())


func test_cards_say_what_each_is() -> void:
	dialog.project_dir = "/p"
	dialog.query = "x"
	dialog.show_results([_asset("Camera", StoreAsset.Kind.PLUGIN, ["3D", "Tool"]),
		_asset("Pixel Pack", StoreAsset.Kind.CONTENT, ["2D", "Pixel Art"]),
		_asset("Agua", StoreAsset.Kind.UNKNOWN)])
	var cards := _cards()
	assert_eq(_text(cards[0], "Kind"), "Plugin")
	assert_eq(_text(cards[1], "Kind"), "Recursos")
	assert_has(cards[1].find_child("Kind", true, false).tooltip_text, "según sus etiquetas del Store")
	assert_true(cards[2].find_child("Kind", true, false) == null, "si no se sabe, no dice nada")
	assert_eq(_text(cards[1], "Tags"), "2D · Pixel Art")
	assert_eq(_text(cards[0], "Meta"), "Pub · MIT · reseñas: 81% · Asset Store")
	assert_eq((cards[0].find_child("View", true, false) as Button).text, "Ver en el Store")
	assert_true(cards[0].find_child("Featured", true, false) == null)
	assert_eq(_text(cards[1].find_child("Thumbnail", true, false), "Initials"), "PP", "sin imagen: las iniciales")
	assert_eq((dialog.get_node("%SearchStatus") as Label).text, "Resultados para «x»: 3")


func test_add_emits_source() -> void:
	var got: Array = []
	dialog.add_requested.connect(func(source: String, pin: bool) -> void: got.append([source, pin]))
	dialog.show_results([_asset("Camera", StoreAsset.Kind.PLUGIN)])
	(dialog.get_node("%Pin") as CheckBox).button_pressed = true
	(_cards()[0].find_child("Add", true, false) as Button).pressed.emit()
	assert_eq(got, [["store:pub/camera", true]])


func test_initials() -> void:
	assert_eq(dialog.initials_of("Phantom Camera"), "PC")
	assert_eq(dialog.initials_of("@icons — Custom node icons"), "IC")
	assert_eq(dialog.initials_of("Terrain3D"), "T")
	assert_eq(dialog.initials_of("—"), "?")


func test_texture_from_bytes() -> void:
	var image := Image.create(400, 300, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	var png := ThumbnailLoader.texture_from_bytes(image.save_png_to_buffer())
	assert_true(png != null, "PNG")
	assert_eq(png.get_height(), ThumbnailLoader.HEIGHT, "achicada")
	assert_eq(png.get_width(), 192, "con la misma proporción")
	var svg := ThumbnailLoader.texture_from_bytes('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><rect width="16" height="16"/></svg>'.to_utf8_buffer())
	assert_true(svg != null, "SVG")
	assert_true(ThumbnailLoader.texture_from_bytes("no es una imagen".to_utf8_buffer()) == null)
	assert_true(ThumbnailLoader.texture_from_bytes(PackedByteArray()) == null)


func test_loader_uses_disk_cache() -> void:
	var loader := ThumbnailLoader.new()
	loader.cache_dir = "user://test_thumbnails"
	tree.root.add_child(loader)
	var url := "https://example.invalid/a.png"
	var image := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(loader.cache_dir)
	FileAccess.open(loader._cache_path(url), FileAccess.WRITE).store_buffer(image.save_png_to_buffer())
	var target := TextureRect.new()
	loader.load_into(url, target)
	assert_true(target.texture != null, "de la caché, sin bajar nada")
	loader.enabled = false
	var other := TextureRect.new()
	loader.load_into("https://example.invalid/b.png", other)
	assert_true(other.texture == null and loader._queue.is_empty(), "apagado no baja")
	DirAccess.remove_absolute(loader._cache_path(url))
	DirAccess.remove_absolute(loader.cache_dir)
	target.free()
	other.free()
	loader.queue_free()
