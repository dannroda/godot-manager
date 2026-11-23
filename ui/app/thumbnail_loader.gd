class_name ThumbnailLoader
extends Node
## Miniaturas de los assets del Store (y de los plugins sugeridos): las baja
## una vez, las guarda en `user://thumbnails/` y las pone en un TextureRect.
## Son solo imagen: si una no baja o no se puede leer, queda el reemplazo que
## tenga el TextureRect (las iniciales: un hermano llamado "Initials", que se
## esconde cuando llega la imagen). Hasta MAX_PARALLEL descargas juntas.

const CACHE_DIR := "user://thumbnails"
const MAX_PARALLEL := 4
## Las imágenes se achican a este alto (las del Store son de 1080 px).
const HEIGHT := 144
const MAX_BYTES := 4 * 1024 * 1024

## Apagado no baja nada (los tests, sin red).
var enabled := true
var cache_dir := CACHE_DIR

var _textures := {}  # url -> Texture2D (o null si falló)
var _waiting := {}  # url -> Array[TextureRect]
var _queue: PackedStringArray = []
var _running := 0


## Pone en `target` la imagen de `url` cuando esté (ya, si está en memoria).
func load_into(url: String, target: TextureRect) -> void:
	if url.is_empty() or not enabled:
		return
	if _textures.has(url):
		if _textures[url] != null:
			_show(target, _textures[url])
		return
	var texture := _from_disk(url)
	if texture != null:
		_textures[url] = texture
		_show(target, texture)
		return
	if _waiting.has(url):
		_waiting[url].append(target)
		return
	_waiting[url] = [target]
	_queue.append(url)
	_next()


## La textura de los bytes de una imagen (PNG, JPEG, WebP o SVG), achicada a
## HEIGHT de alto; null si no se puede leer.
static func texture_from_bytes(data: PackedByteArray) -> Texture2D:
	if data.is_empty():
		return null
	var image := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if data.size() > 8 and data.slice(0, 8) == PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]):
		err = image.load_png_from_buffer(data)
	elif data.size() > 3 and data[0] == 0xFF and data[1] == 0xD8:
		err = image.load_jpg_from_buffer(data)
	elif data.size() > 12 and data.slice(0, 4).get_string_from_ascii() == "RIFF" and data.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = image.load_webp_from_buffer(data)
	else:
		var head := data.slice(0, mini(data.size(), 512)).get_string_from_utf8()
		if head.contains("<svg"):
			err = image.load_svg_from_buffer(data, 4.0)
	if err != OK or image.is_empty():
		return null
	if image.get_height() > HEIGHT:
		var width := maxi(1, roundi(image.get_width() * float(HEIGHT) / image.get_height()))
		image.resize(width, HEIGHT, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)


static func _show(target: TextureRect, texture: Texture2D) -> void:
	target.texture = texture
	var initials := target.get_parent().get_node_or_null(^"Initials") as CanvasItem if target.get_parent() != null else null
	if initials != null:
		initials.visible = false


func _cache_path(url: String) -> String:
	return cache_dir.path_join(url.md5_text())


func _from_disk(url: String) -> Texture2D:
	var path := _cache_path(url)
	if not FileAccess.file_exists(path):
		return null
	return texture_from_bytes(FileAccess.get_file_as_bytes(path))


func _next() -> void:
	while _running < MAX_PARALLEL and not _queue.is_empty():
		var url := _queue[0]
		_queue.remove_at(0)
		_running += 1
		_download(url)


func _download(url: String) -> void:
	var http := HTTPRequest.new()
	http.timeout = 20.0
	http.body_size_limit = MAX_BYTES
	add_child(http)
	var texture: Texture2D = null
	if http.request(url) == OK:
		var result: Array = await http.request_completed
		var body: PackedByteArray = result[3]
		if result[0] == HTTPRequest.RESULT_SUCCESS and int(result[1]) == 200:
			texture = texture_from_bytes(body)
			if texture != null:
				DirAccess.make_dir_recursive_absolute(cache_dir)
				var f := FileAccess.open(_cache_path(url), FileAccess.WRITE)
				if f != null:
					f.store_buffer(body)
	http.queue_free()
	_textures[url] = texture
	# Una tarjeta que se borró mientras bajaba (otra búsqueda) ya no está.
	for target: Variant in _waiting.get(url, []):
		if texture != null and is_instance_valid(target):
			_show(target, texture)
	_waiting.erase(url)
	_running -= 1
	_next()
