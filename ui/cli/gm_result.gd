class_name GmResult
extends RefCounted
## Resultado de parsear una salida del CLI: `value` si ok, `error` si no.

var ok := false
var value: Variant
var error: CliError


static func success(p_value: Variant) -> GmResult:
	var r := GmResult.new()
	r.ok = true
	r.value = p_value
	return r


static func failure(p_error: CliError) -> GmResult:
	var r := GmResult.new()
	r.error = p_error
	return r
