class_name PruneReport
extends RefCounted
## Lo que borra (o borró) `godot-manager --json prune`.

## Una versión sin usar, con sus export templates si se borran con ella.
class Candidate:
	extends RefCounted
	var version := ""
	var size := 0
	## Vacío si no tiene templates.
	var templates_dir := ""
	var templates_size := 0

var candidates: Array[Candidate] = []
## Bytes en total (versiones y templates).
var total := 0
## true si las borró (sin --dry-run).
var removed := false
