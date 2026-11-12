package manager

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
)

var templatePlatforms = []string{"android", "ios", "linux", "macos", "visionos", "web", "windows"}

// Carpeta de templates que espera el editor para un tag oficial:
// "4.8-beta1" -> "4.8.beta1", "4.3-stable" -> "4.3.stable", + ".mono".
func templatesName(ver string, mono bool) string {
	name := strings.Replace(ver, "-", ".", 1)
	if mono {
		name += ".mono"
	}
	return name
}

// Valida una lista "linux,web" de plataformas.
func parsePlatforms(list string) ([]string, error) {
	var out []string
	for _, p := range splitList(list) {
		if !slices.Contains(templatePlatforms, p) {
			return nil, fmt.Errorf("plataforma desconocida '%s' (validas: %s)", p, strings.Join(templatePlatforms, " "))
		}
		out = append(out, p)
	}
	if len(out) == 0 {
		return nil, errors.New("--platforms necesita al menos una plataforma")
	}
	return out, nil
}

func splitList(s string) []string {
	var out []string
	for _, p := range strings.Split(s, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}

// Los archivos de cada plataforma en el tpz empiezan con su nombre
// (linux_debug.x86_64, macos.zip, web_release.zip...).
func platformInstalled(dest, platform string) bool {
	ents, _ := os.ReadDir(dest)
	for _, e := range ents {
		if strings.HasPrefix(e.Name(), platform) && !strings.HasSuffix(e.Name(), ".debugsymbols") {
			return true
		}
	}
	return false
}

// Export templates oficiales. Se instalan donde los busca el editor,
// templatesBase/<version.txt del tpz>. El tpz es un solo zip con todas las
// plataformas; se bajan solo los archivos de las pedidas que falten.
func installTemplates(ver string, mono bool, platforms []string) error {
	name := templatesName(ver, mono)
	dest := filepath.Join(templatesBase, name)
	var missing []string
	for _, p := range platforms {
		if !platformInstalled(dest, p) {
			missing = append(missing, p)
		}
	}
	if len(missing) == 0 {
		fmt.Printf("Los export templates de '%s' (%s) ya estan instalados en %s\n", ver, strings.Join(platforms, " "), dest)
		return nil
	}
	url := githubDL + "/" + ver + "/" + assetPrefix(ver, mono) + "export_templates.tpz"

	if err := os.MkdirAll(templatesBase, 0o755); err != nil {
		return err
	}
	// al lado del destino, para que el rename final no copie entre filesystems
	tmp, err := os.MkdirTemp(templatesBase, ".godot-manager.")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)

	fmt.Printf("Export templates (%s) desde %s\n", strings.Join(missing, " "), url)
	prefixes := []string{"templates/version.txt", "templates/icudt_godot.dat"}
	for _, p := range missing {
		prefixes = append(prefixes, "templates/"+p)
	}
	if err := remoteUnzip(url, tmp, prefixes); err != nil {
		return err
	}

	data, err := os.ReadFile(filepath.Join(tmp, "templates", "version.txt"))
	if err != nil {
		return errors.New("el tpz no tiene version.txt")
	}
	if got := strings.TrimSpace(string(data)); got != name {
		return fmt.Errorf("el tpz es de la version '%s', se esperaba '%s'", got, name)
	}
	if err := moveContents(filepath.Join(tmp, "templates"), dest); err != nil {
		return err
	}
	for _, p := range missing {
		if !platformInstalled(dest, p) {
			warn("'%s' no trae templates de %s", ver, p)
		}
	}
	fmt.Printf("Export templates instalados en %s (%s)\n", dest, humanSize(dirSize(dest)))
	return nil
}

// Si esta instalado el template al que corresponden unos simbolos.
func symbolsTemplateInstalled(dest, id string) bool {
	var f string
	switch {
	case strings.HasPrefix(id, "macos_"):
		f = "macos.zip"
	case strings.HasPrefix(id, "android_"):
		f = id + ".apk"
	default:
		f = id
	}
	_, err := os.Stat(filepath.Join(dest, f))
	return err == nil
}

func exists(p string) bool {
	_, err := os.Lstat(p)
	return err == nil
}

// Desde 4.8-beta1 hay simbolos de debug por template:
// Godot_v<ver>_[mono_]debugsymbols_<id>.zip, con <id> = linux_debug.x86_64,
// windows_release_x86_64.exe, macos_debug.arm64, android_release, etc.
// Los de linux/windows son un <id>.debugsymbols que el template referencia por
// nombre (.gnu_debuglink): sirven dejandolos al lado del template, y tambien
// copiandolos al lado de un juego exportado con el. Verificados contra el
// digest sha256 de la API de GitHub.
//
// spec: ids, plataformas (todos los ids de esa plataforma) o "all". Solo se
// bajan los de templates instalados.
func installTemplateSymbols(ver string, mono bool, spec []string) error {
	dest := filepath.Join(templatesBase, templatesName(ver, mono))
	// el editor no escribe version.txt al instalar por plataforma: alcanza con
	// que haya algun template
	if !slices.ContainsFunc(templatePlatforms, func(p string) bool { return platformInstalled(dest, p) }) {
		return fmt.Errorf("los export templates de '%s' no estan instalados en %s", ver, dest)
	}

	rel, err := getRelease(ver)
	if err != nil {
		return err
	}
	prefix := assetPrefix(ver, mono) + "debugsymbols_"
	var available []string
	for _, a := range rel.Assets {
		if strings.HasPrefix(a.Name, prefix) && strings.HasSuffix(a.Name, ".zip") {
			available = append(available, strings.TrimSuffix(strings.TrimPrefix(a.Name, prefix), ".zip"))
		}
	}
	if len(available) == 0 {
		return fmt.Errorf("la release '%s' no tiene simbolos de debug para los templates (existen desde 4.8-beta1)", ver)
	}

	var ids []string
	for _, item := range spec {
		switch {
		case item == "all":
			ids = append(ids, available...)
		case slices.Contains(templatePlatforms, item):
			for _, id := range available {
				if strings.HasPrefix(id, item+"_") {
					ids = append(ids, id)
				}
			}
		case slices.Contains(available, item):
			if symbolsTemplateInstalled(dest, item) {
				ids = append(ids, item)
			} else {
				warn("el template de '%s' no esta instalado, se omiten sus simbolos", item)
			}
		default:
			return fmt.Errorf("no hay simbolos '%s'. Disponibles: %s", item, strings.Join(available, " "))
		}
	}
	slices.Sort(ids)
	ids = slices.Compact(ids)

	var todo []string
	var total int64
	for _, id := range ids {
		if !symbolsTemplateInstalled(dest, id) {
			continue
		}
		if exists(filepath.Join(dest, id+".debugsymbols")) || exists(filepath.Join(dest, "godot_"+id+".dSYM")) {
			fmt.Printf("'%s' ya tiene los simbolos de debug.\n", id)
			continue
		}
		todo = append(todo, id)
		total += rel.asset(prefix + id + ".zip").Size
	}
	if len(todo) == 0 {
		fmt.Println("No hay simbolos de templates para descargar.")
		return nil
	}

	fmt.Printf("Simbolos de debug a descargar: %s\n", strings.Join(todo, " "))
	fmt.Printf("Total: %s de descarga, ~3x en disco\n", humanSize(total))
	if total > 1<<30 && !confirm("¿Continuar?") {
		fmt.Println("Cancelado.")
		return nil
	}

	tmp, err := os.MkdirTemp(templatesBase, ".godot-manager.")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	for _, id := range todo {
		a := rel.asset(prefix + id + ".zip")
		zipPath := filepath.Join(tmp, id+".zip")
		if err := downloadVerified(githubDL+"/"+ver+"/"+a.Name, zipPath, "sha256", a.sha256()); err != nil {
			return err
		}
		// el de android trae una carpeta por ABI; va aparte para no mezclarla
		into := dest
		if strings.HasPrefix(id, "android") {
			into = filepath.Join(dest, id+".debugsymbols")
		}
		if err := extractZip(zipPath, into, nil); err != nil {
			return err
		}
		os.Remove(zipPath)
		fmt.Printf("Simbolos de %s instalados en %s\n", id, into)
	}
	return nil
}

func cmdTemplates(args []string) error {
	if len(args) == 0 {
		return errors.New("uso: godot-manager templates <version> [--mono] [--platforms=<p>,...] [--debugsymbols[=<id|plataforma>,...|all]] [--debugsymbolsonly]")
	}
	ver := args[0]
	var mono, only, symbolsDefault bool
	var platforms, symbols []string
	for _, opt := range args[1:] {
		switch {
		case opt == "--mono":
			mono = true
		case strings.HasPrefix(opt, "--platforms="):
			p, err := parsePlatforms(strings.TrimPrefix(opt, "--platforms="))
			if err != nil {
				return err
			}
			platforms = p
		case opt == "--debugsymbols":
			symbolsDefault = true
		case strings.HasPrefix(opt, "--debugsymbols="):
			symbols = splitList(strings.TrimPrefix(opt, "--debugsymbols="))
		case opt == "--debugsymbolsonly":
			only = true
		default:
			return fmt.Errorf("opcion desconocida '%s'", opt)
		}
	}
	// sin lista explicita, los simbolos siguen a --platforms; si no se eligieron:
	// los de la plataforma actual, o con --debugsymbolsonly todo lo instalado
	if symbolsDefault || (only && len(symbols) == 0) {
		switch {
		case len(platforms) > 0:
			symbols = platforms
		case only:
			symbols = []string{"all"}
		default:
			symbols = defaultTemplateSymbols()
		}
	}

	if !only {
		p := platforms
		if len(p) == 0 {
			p = templatePlatforms
		}
		if err := installTemplates(ver, mono, p); err != nil {
			return err
		}
	}
	if len(symbols) > 0 {
		return installTemplateSymbols(ver, mono, symbols)
	}
	return nil
}

// Carpeta de export templates que usa un binario. Godot la nombra con
// "<version>.<status>[.mono]", que es su --version sin ".<build>.<hash>"
// (o sin ".<build>" si se compilo fuera de git). Devuelve la que exista.
func templatesDirFor(bin string) string {
	out, err := exec.Command(consoleBinary(bin), "--headless", "--version").Output()
	if err != nil {
		return ""
	}
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	full := strings.TrimSpace(lines[len(lines)-1])
	if full == "" {
		return ""
	}
	for _, n := range []int{2, 1} {
		if c := trimDotSuffixes(full, n); c != "" {
			if d := filepath.Join(templatesBase, c); exists(d) {
				return d
			}
		}
	}
	return ""
}

// Saca los ultimos n segmentos ".algo" de s.
func trimDotSuffixes(s string, n int) string {
	for range n {
		i := strings.LastIndex(s, ".")
		if i < 0 {
			return ""
		}
		s = s[:i]
	}
	return s
}
