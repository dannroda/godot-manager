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
