class_name VersionUpdate
extends RefCounted
## Una versión instalada con una más nueva de su serie, como la devuelve
## `godot-manager --json outdated`.

## La instalada (con -mono si es mono).
var version := ""
## La más nueva de su serie (con -mono).
var latest := ""
## Si la más nueva ya está instalada.
var installed := false
## Página de la release.
var url := ""
