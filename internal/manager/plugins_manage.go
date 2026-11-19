package manager

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
)

// Plugins del Asset Store y de GitHub, con plugins.json (lo que se pide) y plugins.lock (lo que
// quedó instalado) en la raíz del proyecto. Lo hace la librería de pluginkit/ (ver pluginkit.go);
// acá se leen las opciones, se activan los plugins en project.godot y se muestra el resultado.

// Subcomandos de plugins que usan la librería y, con --json, emiten eventos de progreso.
var kitSubcommands = []string{"add", "install", "update", "pin"}

// Opciones de los subcomandos que usan la librería. Devuelve los argumentos que quedan.
type kitFlags struct {
	godot, name               string
	force, pin, pre, noEnable bool
	page                      int
}

func parseKitFlags(args []string, allowed ...string) ([]string, kitFlags, error) {
	var f kitFlags
	var rest []string
	for i := 0; i < len(args); i++ {
		a := args[i]
		key, val, hasVal := strings.Cut(a, "=")
		if !strings.HasPrefix(a, "--") {
			rest = append(rest, a)
			continue
		}
		if !slices.Contains(allowed, key) {
			return nil, f, errf(codeInvalidArgs, "opción desconocida '%s'", a)
		}
		switch key {
		case "--godot", "--name", "--page":
			if !hasVal {
				if i+1 >= len(args) {
					return nil, f, errf(codeInvalidArgs, "falta el valor de %s", key)
				}
				i++
				val = args[i]
			}
			switch key {
			case "--godot":
				f.godot = val
			case "--name":
				f.name = val
			case "--page":
				n, err := strconv.Atoi(val)
				if err != nil || n < 1 {
					return nil, f, errf(codeInvalidArgs, "--page tiene que ser un número desde 1")
				}
				f.page = n
			}
		case "--force":
			f.force = true
		case "--pin":
			f.pin = true
		case "--prerelease":
			f.pre = true
		case "--no-enable":
			f.noEnable = true
		}
	}
	return rest, f, nil
}

func newKitRun(proj string, f kitFlags) kitRun {
	k := kitRun{proj: proj, godot: f.godot, force: f.force}
	if k.godot == "" {
		k.godot = projectGodot(proj)
	}
	return k
}

func warnUnknownGodot(k kitRun) {
	if k.godot == "" {
		out.warn("no se sabe qué Godot usa el proyecto (no tiene .godot-version ni config/features): no se filtran versiones de plugins (usá set-local o --godot)")
	}
}

func cmdPluginsSearch(proj string, args []string) (map[string]any, error) {
	rest, f, err := parseKitFlags(args, "--godot", "--page")
	if err != nil {
		return nil, err
	}
	if len(rest) == 0 {
		return nil, errf(codeInvalidArgs, "uso: godot-manager plugins search <texto> [--page n]")
	}
	k := newKitRun(proj, f)
	page := max(f.page, 1)
	res, err := k.call("search", strings.Join(rest, " "), strconv.Itoa(page))
	if err != nil {
		return nil, err
	}
	if out.isJSON() {
		return res, nil
	}
	assets := anySlice(res["assets"])
	if len(assets) == 0 {
		fmt.Println("No hay resultados en el Asset Store.")
		return nil, nil
	}
	for _, it := range assets {
		a := anyMap(it)
		fmt.Printf("%s  %s (%s)\n", str(a["source"]), str(a["name"]), str(a["publisher"]))
		if d := str(a["description"]); d != "" {
			fmt.Println("    " + d)
		}
	}
	if pages := int(num(res["pages"])); pages > page {
		fmt.Printf("(página %d de %d: --page %d para la siguiente)\n", page, pages, page+1)
	}
	return nil, nil
}

func cmdPluginsAdd(proj string, args []string) (map[string]any, error) {
	rest, f, err := parseKitFlags(args, "--godot", "--name", "--pin", "--prerelease", "--force", "--no-enable")
	if err != nil {
		return nil, err
	}
	if len(rest) != 1 {
		return nil, errf(codeInvalidArgs, "uso: godot-manager plugins add <fuente>[@versión] [--pin] [--name n] [--prerelease] [--no-enable] [--force]")
	}
	k := newKitRun(proj, f)
	warnUnknownGodot(k)
	call := []string{"add", rest[0]}
	if f.name != "" {
		call = append(call, "--name", f.name)
	}
	if f.pin {
		call = append(call, "--pin")
	}
	if f.pre {
		call = append(call, "--prerelease")
	}
	res, err := k.call(call...)
	if err != nil {
		return nil, err
	}
	reportInstalled(res)
	if !f.noEnable {
		enabled, err := enableInstalled(proj, res)
		if err != nil {
			return nil, err
		}
		res["enabled"] = enabled
	}
	return res, nil
}

func cmdPluginsInstall(proj string, args []string) (map[string]any, error) {
	rest, f, err := parseKitFlags(args, "--godot", "--force")
	if err != nil {
		return nil, err
	}
	if len(rest) > 0 {
		return nil, errf(codeInvalidArgs, "sobra '%s' (install instala lo que dice plugins.json)", rest[0])
	}
	if !exists(filepath.Join(proj, "plugins.json")) {
		return nil, errf(codeNoPlugin, "%s no tiene plugins.json (se crea con 'godot-manager plugins add')", proj)
	}
	k := newKitRun(proj, f)
	warnUnknownGodot(k)
	res, err := k.call("install")
	if err != nil {
		return nil, err
	}
	for _, it := range anySlice(res["installed"]) {
		reportInstalled(anyMap(it))
	}
	if ok := anySlice(res["ok"]); len(ok) > 0 {
		out.step("Ya estaban instalados: %s", joinAny(ok))
	}
	if extra := anySlice(res["extra"]); len(extra) > 0 {
		out.warn("plugins.lock tiene plugins que ya no están en plugins.json: %s (godot-manager plugins remove <nombre> los borra)", joinAny(extra))
	}
	return res, nil
}

func cmdPluginsOutdated(proj string, args []string) (map[string]any, error) {
	rest, f, err := parseKitFlags(args, "--godot")
	if err != nil {
		return nil, err
	}
	if len(rest) > 0 {
		return nil, errf(codeInvalidArgs, "sobra '%s'", rest[0])
	}
	k := newKitRun(proj, f)
	warnUnknownGodot(k)
	res, err := k.call("outdated")
	if err != nil {
		return nil, err
	}
	if out.isJSON() {
		return res, nil
	}
	plugins := anySlice(res["plugins"])
	if len(plugins) == 0 {
		fmt.Println("No hay plugins instalados con plugins.json.")
		return nil, nil
	}
	for _, it := range plugins {
		p := anyMap(it)
		line := fmt.Sprintf("%s %s", str(p["name"]), str(p["version"]))
		var notes []string
		if p["newer"] == true {
			line += " -> " + str(p["latest"])
		}
		if p["pinned"] == true {
			notes = append(notes, "fijado")
		}
		if b := anyMap(p["blocked"]); str(b["version"]) != "" {
			notes = append(notes, fmt.Sprintf("%s pide %s", str(b["version"]), godotRange(str(b["godot_min"]), str(b["godot_max"]))))
		}
		if p["incompatible"] == true {
			notes = append(notes, fmt.Sprintf("la instalada no anda con Godot %s", k.godot))
		}
		if len(notes) > 0 {
			line += " (" + strings.Join(notes, "; ") + ")"
		}
		fmt.Println(line)
	}
	return nil, nil
}

func cmdPluginsUpdate(proj string, args []string) (map[string]any, error) {
	rest, f, err := parseKitFlags(args, "--godot", "--force")
	if err != nil {
		return nil, err
	}
	k := newKitRun(proj, f)
	warnUnknownGodot(k)
	res, err := k.call(append([]string{"update"}, rest...)...)
	if err != nil {
		return nil, err
	}
	updated := anySlice(res["updated"])
	for _, it := range updated {
		reportInstalled(anyMap(it))
	}
	for _, it := range anySlice(res["skipped"]) {
		s := anyMap(it)
		switch s["reason"] {
		case "pinned":
			out.step("%s está fijado en %s (godot-manager plugins unpin %s para seguir la más nueva)", str(s["name"]), str(s["version"]), str(s["name"]))
		case "not_installed":
			out.step("%s no está instalado (godot-manager plugins install)", str(s["name"]))
		}
	}
	if len(updated) == 0 {
		out.step("No hay versiones nuevas que anden con Godot %s.", k.godot)
	}
	return res, nil
}

func cmdPluginsPin(proj string, args []string, pin bool) (map[string]any, error) {
	rest, f, err := parseKitFlags(args, "--godot", "--force")
	if err != nil {
		return nil, err
	}
	if !pin {
		if len(rest) != 1 {
			return nil, errf(codeInvalidArgs, "uso: godot-manager plugins unpin <nombre>")
		}
		res, err := newKitRun(proj, f).call("unpin", rest[0])
		if err != nil {
			return nil, err
		}
		out.step("%s ya no está fijado: 'godot-manager plugins update' lo lleva a la versión más nueva", rest[0])
		return res, nil
	}
	if len(rest) < 1 || len(rest) > 2 {
		return nil, errf(codeInvalidArgs, "uso: godot-manager plugins pin <nombre> [versión]")
	}
	res, err := newKitRun(proj, f).call(append([]string{"pin"}, rest...)...)
	if err != nil {
		return nil, err
	}
	if inst := anyMap(res["installed"]); len(inst) > 0 {
		reportInstalled(inst)
	}
	out.step("%s queda fijado en %s", rest[0], str(res["version"]))
	return res, nil
}

// Una línea por plugin instalado o actualizado.
func reportInstalled(r map[string]any) {
	name, version, from := str(r["name"]), str(r["version"]), str(r["from"])
	where := joinAny(anySlice(r["folders"]))
	switch {
	case from == "":
		out.step("Instalado %s %s en %s", name, version, where)
	case from == version:
		out.step("Reinstalado %s %s", name, version)
	default:
		out.step("Actualizado %s: %s -> %s", name, from, version)
	}
	if n := len(anySlice(r["overwritten"])); n > 0 {
		out.warn("se pisaron %d archivos que no eran de %s o se habían cambiado a mano", n, name)
	}
	if r["pinned"] == true {
		out.step("Queda fijado en %s (plugins.json)", version)
	}
}

// Activa en project.godot los plugins que se acaban de instalar. Devuelve los ids activados.
func enableInstalled(proj string, res map[string]any) ([]string, error) {
	var ids []string
	for _, p := range anySlice(res["plugins"]) {
		rel := strings.TrimSuffix(strings.TrimPrefix(str(p), "addons/"), "/plugin.cfg")
		if rel == str(p) {
			continue
		}
		if err := setPluginEnabled(proj, rel, true); err != nil {
			return ids, err
		}
		ids = append(ids, rel)
	}
	if len(ids) > 0 {
		out.step("Activado en project.godot: %s", strings.Join(ids, ", "))
	}
	return ids, nil
}

func joinAny(items []any) string {
	s := make([]string, len(items))
	for i, it := range items {
		s[i] = str(it)
	}
	return strings.Join(s, ", ")
}

// Lo que plugins.lock dice de cada plugin (solo lectura; lo escribe la librería).
type lockEntry struct {
	Source  string   `json:"source"`
	Version string   `json:"version"`
	Folders []string `json:"folders"`
}

type managedPlugin struct {
	Name    string `json:"name"`
	Source  string `json:"source"`
	Version string `json:"version"`
	Pinned  bool   `json:"pinned"`
}

func readLock(proj string) map[string]lockEntry {
	var doc struct {
		Plugins map[string]lockEntry `json:"plugins"`
	}
	data, err := os.ReadFile(filepath.Join(proj, "plugins.lock"))
	if err == nil {
		json.Unmarshal(data, &doc)
	}
	return doc.Plugins
}

func readManifest(proj string) map[string]map[string]any {
	var doc struct {
		Plugins map[string]map[string]any `json:"plugins"`
	}
	data, err := os.ReadFile(filepath.Join(proj, "plugins.json"))
	if err == nil {
		json.Unmarshal(data, &doc)
	}
	return doc.Plugins
}

// Carpeta de addons/ ("x", como los ids de plugin) -> el plugin de plugins.lock que la instaló.
func managedFolders(proj string) map[string]managedPlugin {
	manifest := readManifest(proj)
	result := map[string]managedPlugin{}
	for name, e := range readLock(proj) {
		_, pinned := manifest[name]["version"]
		m := managedPlugin{Name: name, Source: e.Source, Version: e.Version, Pinned: pinned}
		for _, f := range e.Folders {
			result[strings.TrimPrefix(f, "addons/")] = m
		}
	}
	return result
}

// remove de un plugin que está en plugins.lock (por su nombre o por su carpeta): lo borra la
// librería, después de desactivar en project.godot los plugins que trae.
func removeManaged(proj, arg string) (map[string]any, bool, error) {
	lock := readLock(proj)
	name := ""
	if _, ok := lock[arg]; ok {
		name = arg
	} else if m, ok := managedFolders(proj)[arg]; ok {
		name = m.Name
	} else if _, ok := readManifest(proj)[arg]; ok {
		name = arg
	}
	if name == "" {
		return nil, false, nil
	}
	e := lock[name]
	for _, f := range e.Folders {
		p := filepath.Join(proj, filepath.FromSlash(f))
		if isDir(p) {
			out.step("Se va a borrar %s (%s)", p, humanSize(dirSize(p)))
		}
	}
	ok, err := confirm(fmt.Sprintf("¿Desinstalar el plugin '%s' (%s %s)?", name, e.Source, e.Version))
	if err != nil {
		return nil, true, err
	}
	if !ok {
		out.step("Cancelado.")
		return nil, true, nil
	}
	ps, err := projectPlugins(proj)
	if err != nil {
		return nil, true, err
	}
	for _, p := range ps {
		for _, f := range e.Folders {
			if p.Enabled && (p.ID == strings.TrimPrefix(f, "addons/") || strings.HasPrefix(p.ID, strings.TrimPrefix(f, "addons/")+"/")) {
				if err := setPluginEnabled(proj, p.ID, false); err != nil {
					return nil, true, err
				}
			}
		}
	}
	res, err := kitRun{proj: proj}.call("remove", name)
	if err != nil {
		return nil, true, err
	}
	if mod := anySlice(res["modified"]); len(mod) > 0 {
		out.warn("se borraron %d archivos que se habían cambiado a mano", len(mod))
	}
	if left := anySlice(res["left"]); len(left) > 0 {
		out.warn("quedaron archivos que no instaló el plugin en %s", joinAny(left))
	}
	out.step("Plugin '%s' desinstalado (y fuera de plugins.json)", name)
	return res, true, nil
}
