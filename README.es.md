# godot-manager

[English](README.md) · **Español**

Un gestor de versiones de [Godot](https://godotengine.org) para Linux y Windows. Instala builds oficiales (stable, dev, .NET/mono), export templates y símbolos de debug, y elige el editor que corresponde a cada proyecto mediante un archivo `.godot-version`.

Tiene dos partes:

- **`godot-manager`**: una herramienta de línea de comandos escrita en Go, con un `godot` que corre la versión que pide el proyecto actual.
- **Una interfaz gráfica opcional** parecida al Project Manager de Godot. Es un proyecto de Godot en [`ui/`](ui/) y hace todo a través de la salida `--json` del CLI.

![Proyectos](docs/screenshots/projects.png)

## Qué hace

- Instala cualquier release de [godotengine/godot-builds](https://github.com/godotengine/godot-builds), incluido el editor .NET (mono), y verifica cada descarga contra el checksum oficial SHA-512 o SHA-256.
- Define una versión default global y una versión por proyecto. La del proyecto está en un archivo `.godot-version`, que `godot` encuentra subiendo desde la carpeta actual.
- Instala export templates solo de las plataformas que pidas. Lee los archivos que hacen falta directo del `.tpz` remoto, así que no baja el archivo entero.
- Instala símbolos de debug del editor y de los templates (desde Godot 4.8-beta1).
- Acepta builds propios con `godot-manager add`.
- Soporta Godot 3.x. En Linux eso incluye el editor, mono y los templates.
- Tiene una salida `--json` para scripts y para la interfaz: un objeto con el resultado, o un evento por línea (progreso, avisos, errores) en las operaciones largas.

## Capturas

| Versiones instaladas | Releases disponibles |
|---|---|
| ![Versiones instaladas](docs/screenshots/installed.png) | ![Releases disponibles](docs/screenshots/download.png) |

![Diálogo de instalación](docs/screenshots/install-dialog.png)

Por ahora la interfaz está solo en español.

## Instalación

### Arch Linux

```sh
git clone git@github.com:dannroda/godot-manager.git
cd godot-manager
makepkg -si
```

Instala `/usr/bin/godot-manager` y `/usr/bin/godot`.

### Otros sistemas (Linux, Windows)

Hace falta Go 1.24 o posterior:

```sh
make dist   # dist/<os>-<arch>/godot-manager[.exe] y godot[.exe]
```

Los binarios son estáticos y no tienen dependencias. `make dist` los compila para linux y windows en amd64 y arm64. Poné `godot-manager` y `godot` en una carpeta que esté en el `PATH`.

### Dónde guarda las cosas

| | Linux | Windows |
|---|---|---|
| Versiones (`GODOT_DIR`) | `/opt/godot` (tu usuario tiene que poder escribir ahí) | `%LOCALAPPDATA%\godot-manager` |
| Export templates | `~/.local/share/godot/export_templates` | `%APPDATA%\Godot\export_templates` |

Definí `GODOT_DIR` para guardar las versiones en otro lado. Los templates van donde los busca el editor de Godot, así que el editor los puede usar enseguida.

## Uso

```sh
godot-manager list-remote stable        # releases disponibles en GitHub
godot-manager install 4.7.2-stable      # descarga, verifica e instala
godot-manager install 4.7.2-stable --mono --templates --platforms=linux,windows
godot-manager set 4.7.2-stable          # default global

cd mi-juego
godot-manager set-local 4.8-beta3       # escribe .godot-version
godot -e                                # abre 4.8-beta3 en este proyecto
godot-manager which                     # qué binario usaría 'godot' acá

godot-manager templates 4.8-beta3 --platforms=web
godot-manager symbols 4.8-beta3         # símbolos de debug del editor
godot-manager add mi-build ~/godot/bin/godot.linuxbsd.editor.x86_64
godot-manager launch --detach 4.5.1-stable
godot-manager remove 4.5.1-stable
```

`godot-manager help` lista todos los comandos y opciones.

### Salida JSON

Con `--json`, `godot-manager` escribe solo JSON en stdout:

- **`list`, `list-remote` y `which`** muestran sus datos.
- **`install`, `templates` y `symbols`** muestran un evento por línea (`step`, `download`, `warn`). La última línea es siempre `done` o `error`.
- **Los demás comandos** muestran `{"ok": true, ...}` o `{"error": {"code": "...", "message": "..."}}`.

Los códigos de error no cambian entre versiones, así que un script puede decidir según ellos: `not_installed`, `no_default`, `rate_limited`, `bad_token`, etc. `--dir <carpeta>` corre un comando como si se hubiera lanzado en esa carpeta.

Sin terminal, cualquier comando que pediría confirmación falla con `needs_confirmation`; pasá `--yes` para confirmar de antemano.

### Token de GitHub

`list-remote` y algunos pasos de la instalación usan la API de GitHub. Sin token, GitHub permite 60 pedidos por hora. Para subir ese límite, definí `GITHUB_TOKEN` con un token personal; no necesita ningún permiso.

## La interfaz

La interfaz es un proyecto de Godot 4.8 en [`ui/`](ui/). Busca `godot-manager` en el `PATH`, o usa la ruta que le pongas en Ajustes. Para usarla, abrí `ui/` con Godot 4.8 o posterior, o exportala con el preset de Linux o Windows de `ui/export_presets.cfg`.

Tiene tres pestañas:

- **Proyectos**: tu lista de proyectos, la versión que usa cada uno y botones para abrirlo, correrlo, cambiarle la versión o instalar la que falta. Puede importar la lista del Project Manager de Godot.
- **Versiones**: las versiones instaladas, con botones para elegir la default, agregar export templates y símbolos de debug, o sumar un build propio.
- **Descargar**: las releases oficiales, con filtros, tamaños y un diálogo de instalación.

## Desarrollo

```sh
go test ./...                    # tests del CLI
godot --headless --path ui -s res://tests/run_tests.gd   # tests de la interfaz
```

El tablero de tareas de la interfaz está en `ui/compass` (formato Scope Compass).
