class_name CliError
extends RefCounted
## Un error: el que devolvió el CLI ({"error":{code,message,…}} o un evento
## error) o uno de la UI al leer la salida (código `bad_output`, `no_binary`…).

## Códigos propios de la UI (los del CLI vienen tal cual).
const BAD_OUTPUT := "bad_output"
const NO_BINARY := "no_binary"
const START_FAILED := "start_failed"
const EXIT_CODE := "exit_code"

var code := ""
var message := ""
## Campos extra del CLI (por ejemplo `version` y `source` en which).
var extra := {}


static func make(p_code: String, p_message: String, p_extra: Dictionary = {}) -> CliError:
	var e := CliError.new()
	e.code = p_code
	e.message = p_message
	e.extra = p_extra
	return e


func _to_string() -> String:
	return "%s: %s" % [code, message]
