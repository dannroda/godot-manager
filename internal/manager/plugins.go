package manager

import (
	"bufio"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"sort"
	"strconv"
	"strings"
)

// Plugins de editor de un proyecto: los que hay en addons/ (cada carpeta con
// un plugin.cfg) y los que project.godot tiene activos en
// [editor_plugins] enabled. Sirve para destrabar un proyecto que no abre por
// un plugin roto: se desactiva sin abrir el editor.
//
// project.godot se edita a mano y solo en la linea `enabled`, para no
// cambiar el resto del archivo. Godot 4 guarda la ruta del plugin.cfg
// (PackedStringArray("res://addons/x/plugin.cfg")); Godot 3, el nombre de la
// carpeta (PoolStringArray( "x" )).

type plugin struct {
	ID          string   `json:"id"` // carpeta dentro de addons/ (puede tener /)
	Name        string   `json:"name"`
	Description string   `json:"description"`
	Author      string   `json:"author"`
	Version     string   `json:"version"`
	Script      string   `json:"script"`
	Path        string   `json:"path"` // carpeta del plugin
	Enabled     bool     `json:"enabled"`
	Missing     bool     `json:"missing"`  // activo en project.godot pero sin carpeta
	Problems    []string `json:"problems"` // vacio si esta bien
}

type pluginList struct {
	Project string   `json:"project"` // carpeta del proyecto
	Plugins []plugin `json:"plugins"`
}

func cmdPlugins(args []string) (map[string]any, error) {
	sub := "list"
	if len(args) > 0 {
		sub, args = args[0], args[1:]
	}
	proj, err := findProject()
	if err != nil {
		return nil, err
	}
	switch sub {
	case "list":
		if len(args) > 0 {
			return nil, errf(codeInvalidArgs, "sobra '%s'", args[0])
		}
		return nil, listPlugins(proj)
	case "enable", "disable", "remove":
		if len(args) != 1 || strings.HasPrefix(args[0], "-") {
			return nil, errf(codeInvalidArgs, "uso: godot-manager plugins %s <plugin>", sub)
		}
		if sub == "remove" {
			return removePlugin(proj, args[0])
		}
		return enablePlugin(proj, args[0], sub == "enable")
	}
	return nil, errf(codeInvalidArgs, "subcomando desconocido '%s' (list, enable, disable, remove)", sub)
}

// Carpeta con project.godot: la actual o una de mas arriba.
func findProject() (string, error) {
	wd, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for dir := wd; ; {
		if fi, err := os.Stat(filepath.Join(dir, "project.godot")); err == nil && !fi.IsDir() {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", errf(codeNotAProject, "%s no es un proyecto de Godot (no hay project.godot)", wd)
		}
		dir = parent
	}
}

func listPlugins(proj string) error {
	ps, err := projectPlugins(proj)
	if err != nil {
		return err
	}
	if out.isJSON() {
		return printJSON(pluginList{Project: proj, Plugins: ps})
	}
	if len(ps) == 0 {
		fmt.Println("No hay plugins en", filepath.Join(proj, "addons"))
		return nil
	}
	for _, p := range ps {
		mark := " "
		if p.Enabled {
			mark = "*"
		}
		line := fmt.Sprintf("%s %s", mark, p.ID)
		if p.Name != "" && p.Name != p.ID {
			line += fmt.Sprintf(" (%s)", p.Name)
		}
		if p.Version != "" {
			line += " " + p.Version
		}
		fmt.Println(line)
		for _, pr := range p.Problems {
			fmt.Println("    ! " + pr)
		}
	}
	fmt.Println("(* = activo)")
	return nil
}

func projectPlugins(proj string) ([]plugin, error) {
	pf, err := readProjectFile(proj)
	if err != nil {
		return nil, err
	}
	enabled := map[string]bool{}
	for _, e := range pf.enabled {
		enabled[pluginID(e)] = true
	}
	var ps []plugin
	for _, id := range findPluginDirs(filepath.Join(proj, "addons")) {
		p := readPlugin(proj, id)
		p.Enabled = enabled[id]
		delete(enabled, id)
		ps = append(ps, p)
	}
	for id := range enabled {
		ps = append(ps, plugin{
			ID: id, Path: filepath.Join(proj, "addons", filepath.FromSlash(id)),
			Enabled: true, Missing: true,
			Problems: []string{"está activo en project.godot pero la carpeta no existe"},
		})
	}
	sort.Slice(ps, func(i, j int) bool { return ps[i].ID < ps[j].ID })
	return ps, nil
}

// Carpetas de addons/ que tienen un plugin.cfg, relativas a addons/ y con /.
// No entra en la carpeta de un plugin (sus subcarpetas son del plugin).
func findPluginDirs(addons string) []string {
	var ids []string
	filepath.WalkDir(addons, func(path string, d fs.DirEntry, err error) error {
		if err != nil || !d.IsDir() || path == addons {
			return nil
		}
		rel, _ := filepath.Rel(addons, path)
		if strings.Count(filepath.ToSlash(rel), "/") >= 3 {
			return fs.SkipDir
		}
		if fi, err := os.Stat(filepath.Join(path, "plugin.cfg")); err == nil && !fi.IsDir() {
			ids = append(ids, filepath.ToSlash(rel))
			return fs.SkipDir
		}
		return nil
	})
	return ids
}

func readPlugin(proj, id string) plugin {
	dir := filepath.Join(proj, "addons", filepath.FromSlash(id))
	p := plugin{ID: id, Path: dir, Problems: []string{}}
	data, err := os.ReadFile(filepath.Join(dir, "plugin.cfg"))
	if err != nil {
		p.Problems = append(p.Problems, fmt.Sprintf("no se pudo leer plugin.cfg: %v", err))
		return p
	}
	sections := parseCfg(string(data))
	sec, ok := sections["plugin"]
	if !ok {
		p.Problems = append(p.Problems, "plugin.cfg no tiene la sección [plugin]")
		return p
	}
	p.Name, p.Description, p.Author = sec["name"], sec["description"], sec["author"]
	p.Version, p.Script = sec["version"], sec["script"]
	if p.Name == "" {
		p.Problems = append(p.Problems, "plugin.cfg no tiene name")
	}
	switch {
	case p.Script == "":
		p.Problems = append(p.Problems, "plugin.cfg no tiene script")
	default:
		script := filepath.Join(dir, filepath.FromSlash(p.Script))
		if rest, ok := strings.CutPrefix(p.Script, "res://"); ok {
			script = filepath.Join(proj, filepath.FromSlash(rest))
		}
		if _, err := os.Stat(script); err != nil {
			p.Problems = append(p.Problems, fmt.Sprintf("no existe el script %s", p.Script))
		}
	}
	return p
}

// Id de una entrada de `enabled`: "res://addons/x/plugin.cfg" (Godot 4) o
// "x" (Godot 3).
func pluginID(entry string) string {
	if rest, ok := strings.CutPrefix(entry, "res://addons/"); ok {
		return strings.TrimSuffix(strings.TrimSuffix(rest, "plugin.cfg"), "/")
	}
	return entry
}

// La entrada de `enabled` para un id, en el formato de esa version.
func pluginEntry(id string, godot4 bool) string {
	if godot4 {
		return "res://addons/" + id + "/plugin.cfg"
	}
	return id
}

func enablePlugin(proj, id string, on bool) (map[string]any, error) {
	ps, err := projectPlugins(proj)
	if err != nil {
		return nil, err
	}
	i := slices.IndexFunc(ps, func(p plugin) bool { return p.ID == id })
	if i < 0 || (on && ps[i].Missing) {
		return nil, errf(codeNoPlugin, "no hay un plugin '%s' en %s", id, filepath.Join(proj, "addons"))
	}
	changed := ps[i].Enabled != on
	if changed {
		if err := setPluginEnabled(proj, id, on); err != nil {
			return nil, err
		}
	}
	verb := "desactivado"
	if on {
		verb = "activado"
	}
	if changed {
		out.step("Plugin '%s' %s en %s", id, verb, filepath.Join(proj, "project.godot"))
	} else {
		out.step("El plugin '%s' ya estaba %s", id, verb)
	}
	return map[string]any{"plugin": id, "enabled": on, "changed": changed}, nil
}

func removePlugin(proj, id string) (map[string]any, error) {
	ps, err := projectPlugins(proj)
	if err != nil {
		return nil, err
	}
	i := slices.IndexFunc(ps, func(p plugin) bool { return p.ID == id })
	if i < 0 {
		return nil, errf(codeNoPlugin, "no hay un plugin '%s' en %s", id, filepath.Join(proj, "addons"))
	}
	p := ps[i]
	if !p.Missing {
		out.step("Se va a borrar %s (%s)", p.Path, humanSize(dirSize(p.Path)))
	}
	ok, err := confirm(fmt.Sprintf("¿Desinstalar el plugin '%s'?", id))
	if err != nil {
		return nil, err
	}
	if !ok {
		out.step("Cancelado.")
		return nil, nil
	}
	// primero se desactiva: si borrar falla a mitad, el editor igual abre
	if p.Enabled {
		if err := setPluginEnabled(proj, id, false); err != nil {
			return nil, err
		}
	}
	removed := ""
	if !p.Missing {
		if err := os.RemoveAll(p.Path); err != nil {
			return nil, err
		}
		removed = p.Path
	}
	out.step("Plugin '%s' desinstalado", id)
	return map[string]any{"plugin": id, "removed": removed}, nil
}

// project.godot como lineas, con lo necesario para tocar `enabled`.
type projectFile struct {
	path    string
	lines   []string
	eol     string
	godot4  bool     // config_version=5
	section int      // linea de [editor_plugins], -1 si no hay
	line    int      // linea de enabled=, -1 si no hay
	enabled []string // entradas de enabled
}

var enabledRe = regexp.MustCompile(`^enabled\s*=\s*(Packed|Pool)StringArray\s*\((.*)\)\s*$`)

func readProjectFile(proj string) (*projectFile, error) {
	path := filepath.Join(proj, "project.godot")
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	text := string(data)
	pf := &projectFile{path: path, eol: "\n", section: -1, line: -1}
	if strings.Contains(text, "\r\n") {
		pf.eol = "\r\n"
	}
	pf.lines = strings.Split(strings.ReplaceAll(text, "\r\n", "\n"), "\n")
	cur := ""
	for i, l := range pf.lines {
		t := strings.TrimSpace(l)
		if strings.HasPrefix(t, "[") && strings.HasSuffix(t, "]") {
			cur = t[1 : len(t)-1]
			if cur == "editor_plugins" {
				pf.section = i
			}
			continue
		}
		if cur == "" && strings.HasPrefix(t, "config_version=") {
			v, _ := strconv.Atoi(strings.TrimSpace(strings.TrimPrefix(t, "config_version=")))
			pf.godot4 = v >= 5
		}
		if cur == "editor_plugins" && strings.HasPrefix(t, "enabled") {
			m := enabledRe.FindStringSubmatch(t)
			if m == nil {
				return nil, fmt.Errorf("no se entiende la línea %d de %s: %s", i+1, path, t)
			}
			pf.line = i
			pf.enabled = parseStringList(m[2])
		}
	}
	return pf, nil
}

func setPluginEnabled(proj, id string, on bool) error {
	pf, err := readProjectFile(proj)
	if err != nil {
		return err
	}
	var entries []string
	for _, e := range pf.enabled {
		if pluginID(e) != id {
			entries = append(entries, e)
		}
	}
	if on {
		entries = append(entries, pluginEntry(id, pf.godot4))
	}
	line := formatEnabled(entries, pf.godot4)
	switch {
	case pf.line >= 0:
		pf.lines[pf.line] = line
	case pf.section >= 0:
		pf.lines = slices.Insert(pf.lines, pf.section+1, "", line)
	default:
		// sin seccion: al final, separada por una linea en blanco como las demas
		for len(pf.lines) > 0 && pf.lines[len(pf.lines)-1] == "" {
			pf.lines = pf.lines[:len(pf.lines)-1]
		}
		pf.lines = append(pf.lines, "", "[editor_plugins]", "", line, "")
	}
	return writeFileAtomic(pf.path, []byte(strings.Join(pf.lines, pf.eol)))
}

func formatEnabled(entries []string, godot4 bool) string {
	quoted := make([]string, len(entries))
	for i, e := range entries {
		quoted[i] = `"` + strings.ReplaceAll(strings.ReplaceAll(e, `\`, `\\`), `"`, `\"`) + `"`
	}
	if godot4 {
		return "enabled=PackedStringArray(" + strings.Join(quoted, ", ") + ")"
	}
	if len(quoted) == 0 {
		return "enabled=PoolStringArray(  )"
	}
	return "enabled=PoolStringArray( " + strings.Join(quoted, ", ") + " )"
}

// Las cadenas entre comillas de `"a", "b"`.
func parseStringList(s string) []string {
	var items []string
	for i := 0; i < len(s); i++ {
		if s[i] != '"' {
			continue
		}
		v, n := readQuoted(s[i:])
		items = append(items, v)
		i += n - 1
	}
	return items
}

// Una cadena entre comillas al principio de s (con escapes \" \\ \n \t).
// Devuelve el valor y cuantos bytes ocupa, comillas incluidas.
func readQuoted(s string) (string, int) {
	var b strings.Builder
	for i := 1; i < len(s); i++ {
		switch c := s[i]; c {
		case '"':
			return b.String(), i + 1
		case '\\':
			if i+1 < len(s) {
				i++
				switch s[i] {
				case 'n':
					b.WriteByte('\n')
				case 't':
					b.WriteByte('\t')
				default:
					b.WriteByte(s[i])
				}
			}
		default:
			b.WriteByte(c)
		}
	}
	return b.String(), len(s)
}

// Un .cfg de Godot (ConfigFile): seccion -> clave -> valor. Solo entiende
// valores de cadena (que pueden ocupar varias lineas); los demas quedan
// como texto.
func parseCfg(text string) map[string]map[string]string {
	sections := map[string]map[string]string{}
	cur := ""
	sc := bufio.NewScanner(strings.NewReader(strings.ReplaceAll(text, "\r\n", "\n")))
	sc.Buffer(make([]byte, 64*1024), 1<<20)
	var pendingKey string
	var pending strings.Builder
	for sc.Scan() {
		l := sc.Text()
		if pendingKey != "" {
			pending.WriteString("\n" + l)
			if closedQuote(pending.String()) {
				sections[cur][pendingKey], _ = readQuoted(pending.String())
				pendingKey = ""
			}
			continue
		}
		t := strings.TrimSpace(l)
		if t == "" || strings.HasPrefix(t, ";") || strings.HasPrefix(t, "#") {
			continue
		}
		if strings.HasPrefix(t, "[") && strings.HasSuffix(t, "]") {
			cur = t[1 : len(t)-1]
			if sections[cur] == nil {
				sections[cur] = map[string]string{}
			}
			continue
		}
		k, v, ok := strings.Cut(t, "=")
		if !ok {
			continue
		}
		if sections[cur] == nil {
			sections[cur] = map[string]string{}
		}
		k, v = strings.TrimSpace(k), strings.TrimSpace(v)
		if strings.HasPrefix(v, `"`) {
			if !closedQuote(v) {
				pendingKey = k
				pending.Reset()
				pending.WriteString(v)
				continue
			}
			v, _ = readQuoted(v)
		}
		sections[cur][k] = v
	}
	return sections
}

// Si la cadena que empieza en s[0] (una comilla) se cierra.
func closedQuote(s string) bool {
	for i := 1; i < len(s); i++ {
		switch s[i] {
		case '\\':
			i++
		case '"':
			return true
		}
	}
	return false
}

// Escribe en un temporal de la misma carpeta y lo renombra, para no dejar
// project.godot a medio escribir. Mantiene los permisos.
func writeFileAtomic(path string, data []byte) error {
	mode := fs.FileMode(0o644)
	if fi, err := os.Stat(path); err == nil {
		mode = fi.Mode().Perm()
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".project.godot.*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmp.Name(), mode); err != nil {
		return err
	}
	if err := os.Rename(tmp.Name(), path); err != nil {
		return errors.Join(fmt.Errorf("no se pudo escribir %s", path), err)
	}
	return nil
}
