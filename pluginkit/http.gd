extends RefCounted
## Pedidos HTTP con un HTTPRequest colgado de `host` (cualquier nodo dentro del árbol). Los tests
## lo reemplazan por uno falso con los mismos dos métodos.

const TIMEOUT_S := 120.0

var host: Node
var user_agent := "godot-plugin-kit"


func _init(host_node: Node = null) -> void:
	host = host_node


## `{data, error, status}`: data es el JSON ya parseado.
func get_json(url: String) -> Dictionary:
	var response := await _request(url, "")
	if not response.error.is_empty():
		return {"data": null, "error": response.error, "status": response.status}
	var json := JSON.new()
	if json.parse(response.body.get_string_from_utf8()) != OK:
		return {"data": null, "error": "bad_response", "status": response.status}
	return {"data": json.data, "error": "", "status": response.status}


## Baja `url` a `path`. `{error, status}`.
func download(url: String, path: String) -> Dictionary:
	var response := await _request(url, path)
	return {"error": response.error, "status": response.status}


func _request(url: String, path: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_S
	http.download_file = path
	http.max_redirects = 10
	host.add_child(http)
	var headers := PackedStringArray(["User-Agent: " + user_agent])
	if url.begins_with("https://api.github.com/"):
		headers.append("Accept: application/vnd.github+json")
		var token := OS.get_environment("GITHUB_TOKEN")
		if token.is_empty():
			token = OS.get_environment("GH_TOKEN")
		if not token.is_empty():
			headers.append("Authorization: Bearer " + token)
	if http.request(url, headers) != OK:
		http.queue_free()
		return {"body": PackedByteArray(), "error": "no_connection", "status": 0}
	var result: Array = await http.request_completed
	http.queue_free()
	var status := int(result[1])
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"body": PackedByteArray(), "error": "no_connection", "status": status}
	if status == 404:
		return {"body": PackedByteArray(), "error": "not_found", "status": status}
	if status == 403 or status == 429:
		return {"body": PackedByteArray(), "error": "rate_limited", "status": status}
	if status != 200:
		return {"body": PackedByteArray(), "error": "http_error", "status": status}
	return {"body": result[3], "error": "", "status": status}
