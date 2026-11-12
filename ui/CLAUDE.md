# Godot Manager UI

Interfaz gráfica opcional de `godot-manager`, el CLI en Go que vive en la raíz del repo (`../cmd`, `../internal/manager`). Se parece al Project Manager de Godot.

- La UI no reimplementa lógica: todo pasa por `godot-manager --json <comando>` (salida JSON en `list`, `list-remote` y `which`). Si falta algo en el CLI, se anota como tarea con la etiqueta `cli` y no se toca desde este proyecto.
- Godot 4.8-beta3 (`.godot-version`), GDScript con tipado estático, renderer Compatibility. Tiene que andar en Linux y Windows.
- `addons/godot_agent` y `addons/scope_compass` son herramientas del editor: no se modifican.

El tablero de tareas se maneja con scompass; leé `compass/AGENTS.md` antes de tocarlo.
