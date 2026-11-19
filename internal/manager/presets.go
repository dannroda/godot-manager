package manager

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// Presets de plugins: los que uno suele usar, para sumarlos a un proyecto de una vez (plugins
// apply, new --preset). Cada uno es un archivo con la forma de plugins.json en
// $GODOT_DIR/presets/<nombre>.json; un plugin con `version` queda fijado en esa versión en los
// proyectos que lo usen (para un Godot viejo, por ejemplo).

type presetPlugin struct {
	Name       string `json:"name"`
	Source     string `json:"source"`
	Version    string `json:"version"` // "" = la más nueva que ande
	Prerelease bool   `json:"prerelease"`
}

type preset struct {
	Name    string         `json:"name"`
	Path    string         `json:"path"`
	Plugins []presetPlugin `json:"plugins"`
}

func presetsDir() string { return filepath.Join(godotDir, "presets") }

func presetPath(name string) (string, error) {
	if !validName(name) || strings.HasSuffix(name, ".json") {
		return "", errf(codeInvalidArgs, "nombre de preset inválido: '%s'", name)
	}
	return filepath.Join(presetsDir(), name+".json"), nil
}

// Un preset por nombre, o un archivo .json con esa forma.
func findPreset(arg string) (string, error) {
	if strings.HasSuffix(arg, ".json") && exists(arg) {
		return filepath.Abs(arg)
	}
	p, err := presetPath(arg)
	if err != nil {
		return "", err
	}
	if !exists(p) {
		return "", errf(codeNoPreset, "no hay un preset '%s' (ver 'godot-manager presets')", arg)
	}
	return p, nil
}

// Lee un archivo con la forma de plugins.json: el documento entero y sus plugins.
func readPluginsFile(path string) (map[string]any, map[string]map[string]any, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, nil, err
	}
	var doc map[string]any
	if err := json.Unmarshal(data, &doc); err != nil {
		return nil, nil, errf(codeInvalidArgs, "%s no es JSON válido: %v", path, err)
	}
	plugins := map[string]map[string]any{}
	for name, v := range anyMap(doc["plugins"]) {
		if m := anyMap(v); m != nil {
			plugins[name] = m
		}
	}
	return doc, plugins, nil
}

// Como lo escribe la librería: claves ordenadas, dos espacios.
func writePluginsFile(path string, doc map[string]any, plugins map[string]map[string]any) error {
	if doc == nil {
		doc = map[string]any{}
	}
	doc["plugins"] = plugins
	data, err := json.MarshalIndent(doc, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, append(data, '\n'), 0o644)
}

func loadPreset(path string) (preset, error) {
	_, plugins, err := readPluginsFile(path)
	if err != nil {
		return preset{}, err
	}
	p := preset{Name: strings.TrimSuffix(filepath.Base(path), ".json"), Path: path, Plugins: []presetPlugin{}}
	for name, e := range plugins {
		pre, _ := e["prerelease"].(bool)
		p.Plugins = append(p.Plugins, presetPlugin{Name: name, Source: str(e["source"]), Version: str(e["version"]), Prerelease: pre})
	}
	sort.Slice(p.Plugins, func(i, j int) bool { return p.Plugins[i].Name < p.Plugins[j].Name })
	return p, nil
}

func listPresets() []preset {
	ents, _ := os.ReadDir(presetsDir())
	list := []preset{}
	for _, e := range ents {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".json") || strings.HasPrefix(e.Name(), ".") {
			continue
		}
		if p, err := loadPreset(filepath.Join(presetsDir(), e.Name())); err == nil {
			list = append(list, p)
		}
	}
	return list
}

func cmdPresets(args []string) (map[string]any, error) {
	sub := "list"
	if len(args) > 0 {
		sub, args = args[0], args[1:]
	}
	need := func(n int, use string) error {
		if len(args) < n || strings.HasPrefix(args[0], "-") {
			return errf(codeInvalidArgs, "uso: godot-manager presets %s", use)
		}
		return nil
	}
	switch sub {
	case "list":
		list := listPresets()
		if out.isJSON() {
			return nil, printJSON(map[string]any{"dir": presetsDir(), "presets": list})
		}
		if len(list) == 0 {
			fmt.Println("No hay presets (se crean con 'godot-manager presets save <nombre>' en un proyecto, o con 'presets add').")
			return nil, nil
		}
		for _, p := range list {
			printPreset(p)
		}
		return nil, nil
	case "show":
		if err := need(1, "show <nombre>"); err != nil {
			return nil, err
		}
		path, err := findPreset(args[0])
		if err != nil {
			return nil, err
		}
		p, err := loadPreset(path)
		if err != nil {
			return nil, err
		}
		if out.isJSON() {
			return nil, printJSON(p)
		}
		printPreset(p)
		return nil, nil
	case "save":
		return cmdPresetSave(args)
	case "add":
		rest, f, err := parseKitFlags(args, "--prerelease")
		if err != nil {
			return nil, err
		}
		if len(rest) < 2 {
			return nil, errf(codeInvalidArgs, "uso: godot-manager presets add <nombre> <fuente>[@versión]... [--prerelease]")
		}
		path, err := presetPath(rest[0])
		if err != nil {
			return nil, err
		}
		call := append([]string{"preset-add", path}, rest[1:]...)
		if f.pre {
			call = append(call, "--prerelease")
		}
		res, err := kitRun{proj: godotDir}.call(call...)
		if err != nil {
			return nil, err
		}
		out.step("Preset '%s': %s", rest[0], joinAny(anySlice(res["added"])))
		return map[string]any{"preset": rest[0], "path": path, "added": res["added"]}, nil
	case "drop":
		if err := need(2, "drop <nombre> <plugin>..."); err != nil {
			return nil, err
		}
		path, err := findPreset(args[0])
		if err != nil {
			return nil, err
		}
		doc, plugins, err := readPluginsFile(path)
		if err != nil {
			return nil, err
		}
		for _, name := range args[1:] {
			if _, ok := plugins[name]; !ok {
				return nil, errf(codeNoPlugin, "el preset '%s' no tiene '%s'", args[0], name)
			}
			delete(plugins, name)
		}
		if err := writePluginsFile(path, doc, plugins); err != nil {
			return nil, err
		}
		out.step("Preset '%s': se sacó %s", args[0], strings.Join(args[1:], ", "))
		return map[string]any{"preset": args[0], "removed": args[1:]}, nil
	case "remove":
		if err := need(1, "remove <nombre>"); err != nil {
			return nil, err
		}
		path, err := findPreset(args[0])
		if err != nil {
			return nil, err
		}
		if err := os.Remove(path); err != nil {
			return nil, err
		}
		out.step("Preset '%s' borrado", args[0])
		return map[string]any{"preset": args[0], "removed": path}, nil
	}
	return nil, errf(codeInvalidArgs, "subcomando desconocido '%s' (list, show, save, add, drop, remove)", sub)
}

func printPreset(p preset) {
	var items []string
	for _, pl := range p.Plugins {
		s := pl.Name
		if pl.Version != "" {
			s += " " + pl.Version
		}
		items = append(items, s)
	}
	fmt.Printf("%s: %s\n", p.Name, strings.Join(items, ", "))
	for _, pl := range p.Plugins {
		fmt.Printf("    %s  %s\n", pl.Name, pl.Source)
	}
}

// presets save <nombre> [--pin] [--force]: los plugins.json del proyecto actual como preset. Con
// --pin, cada plugin queda fijado en la versión que tiene instalada el proyecto.
func cmdPresetSave(args []string) (map[string]any, error) {
	var rest []string
	pin, force := false, false
	for _, a := range args {
		switch a {
		case "--pin":
			pin = true
		case "--force":
			force = true
		default:
			if strings.HasPrefix(a, "-") {
				return nil, errf(codeInvalidArgs, "opción desconocida '%s'", a)
			}
			rest = append(rest, a)
		}
	}
	if len(rest) != 1 {
		return nil, errf(codeInvalidArgs, "uso: godot-manager presets save <nombre> [--pin] [--force] (en un proyecto)")
	}
	path, err := presetPath(rest[0])
	if err != nil {
		return nil, err
	}
	if exists(path) && !force {
		return nil, errf(codeAlreadyInstalled, "ya hay un preset '%s' (con --force se reemplaza)", rest[0])
	}
	proj, err := findProject()
	if err != nil {
		return nil, err
	}
	manifest := filepath.Join(proj, "plugins.json")
	if !exists(manifest) {
		return nil, errf(codeNoPlugin, "%s no tiene plugins.json (se crea con 'godot-manager plugins add')", proj)
	}
	_, plugins, err := readPluginsFile(manifest)
	if err != nil {
		return nil, err
	}
	if len(plugins) == 0 {
		return nil, errf(codeNoPlugin, "plugins.json de %s no tiene plugins", proj)
	}
	if pin {
		lock := readLock(proj)
		for name, e := range plugins {
			if v := lock[name].Version; v != "" {
				e["version"] = v
			}
		}
	}
	if err := writePluginsFile(path, nil, plugins); err != nil {
		return nil, err
	}
	p, _ := loadPreset(path)
	out.step("Preset '%s' guardado con %d plugins (%s)", rest[0], len(p.Plugins), path)
	return map[string]any{"preset": rest[0], "path": path, "plugins": p.Plugins}, nil
}

// plugins apply <preset> [--godot v] [--force] [--no-enable]
func cmdPluginsApply(proj string, args []string) (map[string]any, error) {
	rest, f, err := parseKitFlags(args, "--godot", "--force", "--no-enable")
	if err != nil {
		return nil, err
	}
	if len(rest) != 1 {
		return nil, errf(codeInvalidArgs, "uso: godot-manager plugins apply <preset> [--no-enable] [--force]")
	}
	path, err := findPreset(rest[0])
	if err != nil {
		return nil, err
	}
	k := newKitRun(proj, f)
	warnUnknownGodot(k)
	return applyPreset(k, path, !f.noEnable)
}

func applyPreset(k kitRun, path string, enable bool) (map[string]any, error) {
	res, err := k.call("apply", path)
	if err != nil {
		return nil, err
	}
	added := map[string]bool{}
	for _, n := range anySlice(res["added"]) {
		added[str(n)] = true
	}
	var enabled []string
	for _, it := range anySlice(res["installed"]) {
		r := anyMap(it)
		reportInstalled(r)
		if enable && added[str(r["name"])] {
			ids, err := enableInstalled(k.proj, r)
			if err != nil {
				return nil, err
			}
			enabled = append(enabled, ids...)
		}
	}
	if kept := anySlice(res["kept"]); len(kept) > 0 {
		out.step("Ya estaban en plugins.json: %s", joinAny(kept))
	}
	res["enabled"] = enabled
	return res, nil
}
