package manager

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// outdated, upgrade y prune: versiones con una release mas nueva de la misma
// serie, y versiones que no usa ningun proyecto.

type versionUpdate struct {
	Version   string `json:"version"`   // la instalada (con -mono si es mono)
	Latest    string `json:"latest"`    // la mas nueva de su serie (con -mono)
	Installed bool   `json:"installed"` // si la mas nueva ya esta instalada
	URL       string `json:"url"`       // pagina de la release
}

// La release mas nueva de la misma serie (mayor.menor) que tag, o nil. Una
// estable solo se compara con estables (4.7.1-stable -> 4.7.2-stable); una
// pre-release, con todo lo de su serie (4.8-beta3 -> 4.8-rc1 o 4.8-stable).
// Tiene que traer el editor (mono, si es mono) para esta plataforma.
func newerInSeries(rs []release, tag string, mono bool) *release {
	k, ok := parseTag(tag)
	if !ok {
		return nil
	}
	stable := k[4] == stageRank["stable"]
	names, err := editorAssets("X", mono)
	if err != nil {
		return nil
	}
	var best *release
	for i := range rs {
		r := &rs[i]
		rk, ok := parseTag(r.TagName)
		if !ok || rk[0] != k[0] || rk[1] != k[1] || compareTags(r.TagName, tag) <= 0 {
			continue
		}
		if stable && rk[4] != stageRank["stable"] {
			continue
		}
		if best != nil && compareTags(r.TagName, best.TagName) <= 0 {
			continue
		}
		cands := make([]string, len(names))
		for j, n := range names {
			cands[j] = strings.Replace(n, "_vX_", "_v"+r.TagName+"_", 1)
		}
		if firstAsset(r, cands) != nil {
			best = r
		}
	}
	return best
}

// Las versiones oficiales instaladas que tienen una mas nueva en su serie.
func findUpdates() ([]versionUpdate, error) {
	rs, err := listReleases()
	if err != nil {
		return nil, err
	}
	ups := []versionUpdate{}
	for _, name := range installedVersions() {
		tag := versionTag(name)
		if tag == "" {
			continue
		}
		if _, ok := versionBinary(name); !ok {
			continue
		}
		mono := strings.HasSuffix(name, "-mono")
		r := newerInSeries(rs, tag, mono)
		if r == nil {
			continue
		}
		latest := r.TagName
		if mono {
			latest += "-mono"
		}
		_, installed := versionBinary(latest)
		ups = append(ups, versionUpdate{Version: name, Latest: latest, Installed: installed, URL: r.HTMLURL})
	}
	return ups, nil
}

func cmdOutdated() error {
	ups, err := findUpdates()
	if err != nil {
		return err
	}
	if out.isJSON() {
		return printJSON(map[string]any{"updates": ups})
	}
	if len(ups) == 0 {
		fmt.Println("Todas las versiones instaladas son las ultimas de su serie.")
		return nil
	}
	fmt.Println("Versiones con una mas nueva de la misma serie:")
	for _, u := range ups {
		extra := ""
		if u.Installed {
			extra = " (ya instalada)"
		}
		fmt.Printf("  %s -> %s%s\n", u.Version, u.Latest, extra)
	}
	fmt.Println("Actualiza una con 'godot-manager upgrade <version>'.")
	return nil
}

// upgrade <ver>: instala la mas nueva de su serie con lo mismo que tenia
// (mono, export templates de las mismas plataformas, simbolos del editor) y,
// si era la default, la nueva pasa a serlo. La vieja queda instalada.
func cmdUpgrade(args []string) (map[string]any, error) {
	if len(args) != 1 || strings.HasPrefix(args[0], "-") {
		return nil, errf(codeInvalidArgs, "uso: godot-manager upgrade <version>")
	}
	name := args[0]
	if _, err := requireInstalled(name); err != nil {
		return nil, err
	}
	tag := versionTag(name)
	if tag == "" {
		return nil, errf(codeInvalidArgs, "'%s' no es una version oficial", name)
	}
	mono := strings.HasSuffix(name, "-mono")
	rs, err := listReleases()
	if err != nil {
		return nil, err
	}
	r := newerInSeries(rs, tag, mono)
	if r == nil {
		out.step("'%s' ya es la ultima de su serie", name)
		return map[string]any{"updated": false, "version": name}, nil
	}
	iargs := []string{r.TagName}
	if mono {
		iargs = append(iargs, "--mono")
	}
	if d := officialTemplatesDir(name); d != "" {
		if ps := installedPlatforms(d); len(ps) > 0 {
			iargs = append(iargs, "--platforms="+strings.Join(ps, ","))
		}
	}
	if s, err := editorSymbolsFor(tag, mono); err == nil && exists(filepath.Join(versionsDir, name, s.File)) {
		iargs = append(iargs, "--debugsymbols")
	}
	out.step("Actualizando '%s' a %s", name, r.TagName)
	res, err := cmdInstall(iargs)
	if err != nil {
		return nil, err
	}
	latest := res["version"].(string)
	wasDefault := defaultVersion() == name
	if wasDefault {
		if err := setDefault(latest, res["path"].(string)); err != nil {
			return nil, err
		}
		out.step("Default seteado a %s", latest)
	}
	res["updated"] = true
	res["from"] = name
	res["default"] = wasDefault
	return res, nil
}

// Version que fija un proyecto: su .godot-version, o el de una carpeta de mas
// arriba; "" si no hay.
func projectVersion(dir string) string {
	for {
		if data, err := os.ReadFile(filepath.Join(dir, ".godot-version")); err == nil {
			return strings.TrimSpace(string(data))
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return ""
		}
		dir = parent
	}
}

// Donde guarda su lista el Project Manager de Godot (como la UI).
func godotProjectsCfg() string {
	switch runtime.GOOS {
	case "windows", "darwin":
		d, err := os.UserConfigDir()
		if err != nil {
			return ""
		}
		return filepath.Join(d, "Godot", "projects.cfg")
	}
	d, err := dataHome()
	if err != nil {
		return ""
	}
	return filepath.Join(d, "godot", "projects.cfg")
}

// Las carpetas de la lista del Project Manager: cada seccion [<ruta>] del cfg.
func godotProjects(cfg string) []string {
	f, err := os.Open(cfg)
	if err != nil {
		return nil
	}
	defer f.Close()
	var dirs []string
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		l := strings.TrimSpace(sc.Text())
		if strings.HasPrefix(l, "[") && strings.HasSuffix(l, "]") {
			dirs = append(dirs, filepath.FromSlash(l[1:len(l)-1]))
		}
	}
	return dirs
}

type pruneCandidate struct {
	Version       string `json:"version"`
	Size          int64  `json:"size"`
	TemplatesDir  string `json:"templates_dir"` // "" si no tiene, o si otra version los usa
	TemplatesSize int64  `json:"templates_size"`
}

// prune [--dry-run] [--yes] [<proyecto>...]: borra las versiones oficiales
// que no usa nadie, con sus export templates. Se quedan la default y las que
// fija algun proyecto: los que se pasan, los de la lista del Project Manager
// de Godot y la carpeta actual. Las agregadas con 'add' no se tocan.
func cmdPrune(args []string) (map[string]any, error) {
	dry := false
	projects := []string{}
	for _, a := range args {
		switch {
		case a == "--dry-run":
			dry = true
		case strings.HasPrefix(a, "-"):
			return nil, errf(codeInvalidArgs, "opcion desconocida '%s'", a)
		default:
			projects = append(projects, a)
		}
	}
	projects = append(projects, godotProjects(godotProjectsCfg())...)
	if wd, err := os.Getwd(); err == nil {
		projects = append(projects, wd)
	}

	keep := map[string]bool{}
	if d := defaultVersion(); d != "" {
		keep[d] = true
	}
	for _, p := range projects {
		if v := projectVersion(p); v != "" {
			keep[v] = true
		}
	}
	var gone []string
	for _, v := range installedVersions() {
		if keep[v] || versionTag(v) == "" {
			continue
		}
		if _, ok := versionBinary(v); ok {
			gone = append(gone, v)
		}
	}
	cands := []pruneCandidate{}
	var total int64
	for _, v := range gone {
		c := pruneCandidate{Version: v, Size: dirSize(filepath.Join(versionsDir, v))}
		// cada version oficial tiene su carpeta de templates (por tag y mono)
		if d := officialTemplatesDir(v); d != "" {
			c.TemplatesDir, c.TemplatesSize = d, dirSize(d)
		}
		total += c.Size + c.TemplatesSize
		cands = append(cands, c)
	}
	res := map[string]any{"versions": cands, "total": total, "removed": false}
	if len(cands) == 0 {
		out.step("No hay versiones sin usar.")
		return res, nil
	}
	out.step("Versiones que no usa ningun proyecto conocido:")
	for _, c := range cands {
		line := fmt.Sprintf("  %s (%s)", c.Version, humanSize(c.Size))
		if c.TemplatesDir != "" {
			line += fmt.Sprintf(" + export templates (%s)", humanSize(c.TemplatesSize))
		}
		out.step("%s", line)
	}
	out.step("Total: %s", humanSize(total))
	if dry {
		return res, nil
	}
	ok, err := confirm(fmt.Sprintf("¿Borrar estas %d versiones?", len(cands)))
	if err != nil {
		return nil, err
	}
	if !ok {
		out.step("Cancelado.")
		return nil, nil
	}
	for _, c := range cands {
		if err := os.RemoveAll(filepath.Join(versionsDir, c.Version)); err != nil {
			return nil, err
		}
		if c.TemplatesDir != "" {
			if err := os.RemoveAll(c.TemplatesDir); err != nil {
				return nil, err
			}
		}
	}
	out.step("Liberados %s", humanSize(total))
	res["removed"] = true
	return res, nil
}
