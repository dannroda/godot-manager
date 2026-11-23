class_name StoreAsset
extends RefCounted
## Un resultado de `plugins search` (Asset Store de Godot).

## "store:publisher/slug": lo que se le pasa a `plugins add`.
var source := ""
var name := ""
var publisher := ""
var description := ""
var license := ""
## 0 a 100 (las reseñas del Store).
var score := 0
var store_url := ""
## Las etiquetas del Store, con el nombre que muestra ("3D", "Pixel Art").
var tags: PackedStringArray = []
## URL de la imagen ("" si no tiene).
var thumbnail := ""
## Qué es, estimado por las etiquetas: Kind.PLUGIN (trae código), Kind.CONTENT
## (arte, sonido…) o Kind.UNKNOWN. El Store no lo dice; al instalarlo se sabe.
var kind := Kind.UNKNOWN
## Uno de los nuestros (sugerido), de GitHub: no viene del Store.
var featured := false
## Dónde verlo (la página del Store o el repo).
var page_url := ""

enum Kind { UNKNOWN, PLUGIN, CONTENT }


static func kind_from(text: String) -> Kind:
	match text:
		"plugin":
			return Kind.PLUGIN
		"content":
			return Kind.CONTENT
	return Kind.UNKNOWN
