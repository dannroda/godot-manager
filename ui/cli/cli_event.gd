class_name CliEvent
extends RefCounted
## Una línea de la salida de install / templates / symbols con --json.

enum Kind { STEP, DOWNLOAD, WARN, DONE, ERROR }

var kind := Kind.STEP
## step y warn.
var message := ""
## download: archivo actual y bytes de toda la descarga.
var file := ""
var done := 0
var total := 0
## done: el objeto entero (version, path, templates_dir, platforms, file…).
var data := {}
## error.
var error: CliError


func progress() -> float:
	if total <= 0:
		return -1.0
	return clampf(float(done) / float(total), 0.0, 1.0)


func is_final() -> bool:
	return kind == Kind.DONE or kind == Kind.ERROR
