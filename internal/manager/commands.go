package manager

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

var Version = "dev"

func Main(args []string) int {
	if err := initPaths(); err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		return 1
	}
	asJSON := false
	if len(args) > 0 && args[0] == "--json" {
		asJSON, args = true, args[1:]
	}
	cmd := ""
	if len(args) > 0 {
		cmd, args = args[0], args[1:]
	}
	arg := func(i int) string {
		if i < len(args) {
			return args[i]
		}
		return ""
	}

	var err error
	switch cmd {
	case "list":
		_, asJSON = jsonFlag(args, asJSON)
		err = cmdList(asJSON)
	case "list-remote":
		args, asJSON = jsonFlag(args, asJSON)
		err = cmdListRemote(arg(0), asJSON)
	case "install":
		err = cmdInstall(args)
	case "symbols":
		err = cmdSymbols(arg(0))
	case "templates":
		err = cmdTemplates(args)
	case "add":
		err = cmdAdd(args)
	case "remove":
		err = cmdRemove(arg(0))
	case "set":
		err = cmdSet(arg(0))
	case "set-local":
		err = cmdSetLocal(arg(0))
	case "which":
		_, asJSON = jsonFlag(args, asJSON)
		err = cmdWhich(asJSON)
	case "run":
		var r *resolution
		if r, err = resolve(); err == nil {
			err = execBinary(r.Path, args)
		}
	case "launch":
		var bin string
		if bin, err = requireInstalled(arg(0)); err == nil {
			err = execBinary(bin, args[1:])
		}
	case "version", "--version":
		fmt.Println(Version)
	case "-h", "--help", "help", "":
		usage(os.Stdout)
	default:
		usage(os.Stderr)
		return 1
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		return 1
	}
	return 0
}

type installedVersion struct {
	Name         string `json:"name"`
	Path         string `json:"path"`
	Default      bool   `json:"default"`
	Mono         bool   `json:"mono"`
	DebugSymbols bool   `json:"debug_symbols"`
}

func cmdList(asJSON bool) error {
	def := defaultVersion()
	var list []installedVersion
	for _, name := range installedVersions() {
		bin, ok := versionBinary(name)
		if !ok {
			continue
		}
		dir := filepath.Join(versionsDir, name)
		syms, _ := filepath.Glob(filepath.Join(dir, "*.debugsymbols"))
		list = append(list, installedVersion{
			Name:         name,
			Path:         bin,
			Default:      name == def,
			Mono:         exists(filepath.Join(filepath.Dir(bin), "GodotSharp")),
			DebugSymbols: len(syms) > 0,
		})
	}
	if asJSON {
		if list == nil {
			list = []installedVersion{}
		}
		return printJSON(map[string]any{"default": def, "versions": list})
	}
	fmt.Println("Versiones instaladas:")
	for _, v := range list {
		mark, extra := "   ", ""
		if v.DebugSymbols {
			extra = " [+simbolos]"
		}
		if v.Default {
			mark, extra = "  *", extra+" (default)"
		}
		fmt.Printf("%s %s%s\n", mark, v.Name, extra)
	}
	return nil
}

type remoteVersion struct {
	Tag         string `json:"tag"`
	Prerelease  bool   `json:"prerelease"`
	PublishedAt string `json:"published_at"`
}

func cmdListRemote(filter string, asJSON bool) error {
	rs, err := listReleases()
	if err != nil {
		return err
	}
	pick := func(pre bool) []remoteVersion {
		var out []remoteVersion
		for _, r := range rs {
			if filter == "" || filter == "all" || r.Prerelease == pre {
				out = append(out, remoteVersion{r.TagName, r.Prerelease, r.PublishedAt})
			}
		}
		if out == nil {
			out = []remoteVersion{}
		}
		return out
	}
	first := func(pre bool) string {
		for _, r := range rs {
			if r.Prerelease == pre {
				return r.TagName
			}
		}
		return ""
	}
	print := func(title string, vs []remoteVersion) error {
		if asJSON {
			return printJSON(vs)
		}
		fmt.Println(title)
		for _, v := range vs {
			fmt.Println(v.Tag)
		}
		return nil
	}

	switch filter {
	case "dev":
		return print("Dev snapshots / pre-releases (beta, rc, dev):", pick(true))
	case "stable":
		return print("Versiones estables:", pick(false))
	case "latest":
		if asJSON {
			return printJSON(map[string]string{"stable": first(false), "dev": first(true)})
		}
		fmt.Println("Ultima estable: ", first(false))
		fmt.Println("Ultima dev/pre-release:", first(true))
		return nil
	default:
		filter = ""
		return print("Todas las versiones (usa 'stable', 'dev' o 'latest' para filtrar):", pick(false))
	}
}

func cmdSet(name string) error {
	bin, err := requireInstalled(name)
	if err != nil {
		return err
	}
	if err := setDefault(name, bin); err != nil {
		return err
	}
	fmt.Printf("Default seteado a %s\n", name)
	return nil
}

func cmdSetLocal(name string) error {
	if _, err := requireInstalled(name); err != nil {
		return err
	}
	wd, err := os.Getwd()
	if err != nil {
		return err
	}
	f := filepath.Join(wd, ".godot-version")
	if err := os.WriteFile(f, []byte(name+"\n"), 0o644); err != nil {
		return err
	}
	fmt.Printf("Version local seteada a %s en %s\n", name, f)
	return nil
}

func cmdWhich(asJSON bool) error {
	r, err := resolve()
	if err != nil {
		return err
	}
	if asJSON {
		return printJSON(r)
	}
	fmt.Println(r.Path)
	return nil
}

func cmdAdd(args []string) error {
	if len(args) < 2 {
		return errors.New("uso: godot-manager add <nombre> <ruta-al-binario> [--symlink]")
	}
	name, src := args[0], args[1]
	symlink := len(args) > 2 && args[2] == "--symlink"
	if !validName(name) {
		return fmt.Errorf("nombre invalido '%s'", name)
	}
	if !isExecutable(src) {
		return fmt.Errorf("%s no existe o no es ejecutable", src)
	}
	dir := filepath.Join(versionsDir, name)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	os.Remove(filepath.Join(dir, binMarker))

	if symlink {
		abs, err := filepath.Abs(src)
		if err != nil {
			return err
		}
		if abs, err = filepath.EvalSymlinks(abs); err != nil {
			return err
		}
		if runtime.GOOS == "windows" {
			err = os.WriteFile(filepath.Join(dir, binMarker), []byte(abs+"\n"), 0o644)
		} else {
			link := filepath.Join(dir, "godot")
			os.Remove(link)
			err = os.Symlink(abs, link)
		}
		if err != nil {
			return err
		}
		fmt.Printf("Agregado '%s' como symlink a %s\n", name, src)
		return nil
	}
	dst := filepath.Join(dir, "godot")
	if runtime.GOOS == "windows" {
		dst += ".exe"
	}
	if err := copyFile(src, dst, 0o755); err != nil {
		return err
	}
	fmt.Printf("Agregado '%s' (copiado desde %s)\n", name, src)
	return nil
}

// Desde 4.8-beta1 cada release trae simbolos de debug aparte para el editor
// (linux y windows). El binario oficial los referencia por nombre via
// .gnu_debuglink, asi que alcanza con dejarlos al lado del binario: gdb y
// addr2line los encuentran solos. No estan en el manifest, se verifican
// contra el digest sha256 que expone la API de GitHub para cada asset.
func cmdSymbols(name string) error {
	if name == "" {
		return errors.New("uso: godot-manager symbols <version>[-mono]")
	}
	bin, err := requireInstalled(name)
	if err != nil {
		return err
	}
	ver, mono := strings.CutSuffix(name, "-mono")
	symfile, err := editorSymbolsFile(ver, mono)
	if err != nil {
		return err
	}
	dir := filepath.Dir(bin)
	if !strings.HasPrefix(dir, versionsDir) {
		dir = filepath.Join(versionsDir, name)
	}
	if exists(filepath.Join(dir, symfile)) {
		fmt.Printf("'%s' ya tiene los simbolos de debug.\n", name)
		return nil
	}

	missing := fmt.Errorf("la release '%s' no tiene %s.zip (existen desde 4.8-beta1, y solo para builds oficiales)", ver, symfile)
	rel, err := getRelease(ver)
	if err != nil {
		return missing
	}
	a := rel.asset(symfile + ".zip")
	if a == nil {
		return missing
	}

	tmp, err := os.MkdirTemp(versionsDir, ".godot-manager.")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	fmt.Printf("Simbolos de debug: %s de descarga, ~3x en disco\n", humanSize(a.Size))
	zipPath := filepath.Join(tmp, "symbols.zip")
	if err := downloadVerified(githubDL+"/"+ver+"/"+a.Name, zipPath, "sha256", a.sha256()); err != nil {
		return err
	}
	if err := extractZip(zipPath, dir, func(n string) bool { return n == symfile }); err != nil {
		return err
	}
	if !exists(filepath.Join(dir, symfile)) {
		return fmt.Errorf("el zip no trae %s", symfile)
	}
	fmt.Printf("Simbolos de debug instalados en %s\n", filepath.Join(dir, symfile))
	return nil
}

func cmdInstall(args []string) error {
	if len(args) == 0 {
		return errors.New("uso: godot-manager install <version> [--mono] [--debugsymbols] [--templates] [--platforms=<p>,...]")
	}
	ver := args[0]
	var mono, symbols, templates bool
	platforms := ""
	for _, opt := range args[1:] {
		switch {
		case opt == "--mono":
			mono = true
		case opt == "--debugsymbols":
			symbols = true
		case opt == "--templates":
			templates = true
		case strings.HasPrefix(opt, "--platforms="):
			templates, platforms = true, opt
		default:
			return fmt.Errorf("opcion desconocida '%s'", opt)
		}
	}

	destName := ver
	if mono {
		destName += "-mono"
	}
	if _, ok := versionBinary(destName); ok {
		fmt.Printf("'%s' ya esta instalada.\n", destName)
	} else if err := installEditor(ver, mono, filepath.Join(versionsDir, destName)); err != nil {
		return err
	}

	if symbols {
		if err := cmdSymbols(destName); err != nil {
			return err
		}
	}
	if templates {
		targs := []string{ver}
		if mono {
			targs = append(targs, "--mono")
		}
		if platforms != "" {
			targs = append(targs, platforms)
		}
		if symbols {
			targs = append(targs, "--debugsymbols")
		}
		return cmdTemplates(targs)
	}
	return nil
}

func installEditor(ver string, mono bool, dest string) error {
	rel, err := getRelease(ver)
	if err != nil {
		return err
	}
	candidates, err := editorAssets(ver, mono)
	if err != nil {
		return err
	}
	var a *asset
	for _, c := range candidates {
		if a = rel.asset(c); a != nil {
			break
		}
	}
	if a == nil {
		return fmt.Errorf("la release '%s' no tiene build para esta plataforma (%s)", ver, strings.Join(candidates, ", "))
	}
	algo, sum := "sha512", manifestChecksum(ver, a.Name)
	if sum == "" {
		algo, sum = "sha256", a.sha256()
	}

	if err := os.MkdirAll(versionsDir, 0o755); err != nil {
		return err
	}
	tmp, err := os.MkdirTemp(versionsDir, ".godot-manager.")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	zipPath := filepath.Join(tmp, "godot.zip")
	if err := downloadVerified(githubDL+"/"+ver+"/"+a.Name, zipPath, algo, sum); err != nil {
		return err
	}
	root := filepath.Join(tmp, "extracted")
	if err := extractZip(zipPath, root, nil); err != nil {
		return err
	}
	// los zip mono traen todo dentro de una carpeta (binario + GodotSharp/)
	if ents, _ := os.ReadDir(root); len(ents) == 1 && ents[0].IsDir() {
		root = filepath.Join(root, ents[0].Name())
	}
	if err := moveContents(root, dest); err != nil {
		return err
	}
	if err := setupBinary(dest, mono); err != nil {
		os.RemoveAll(dest)
		return err
	}
	fmt.Printf("Instalado en %s\n", dest)
	return nil
}

// Deja el binario de una version recien extraida donde versionBinary lo busca.
func setupBinary(dest string, mono bool) error {
	switch runtime.GOOS {
	case "windows":
		exes, _ := filepath.Glob(filepath.Join(dest, "Godot_v*.exe"))
		for _, e := range exes {
			if !strings.HasSuffix(e, "_console.exe") {
				return os.WriteFile(filepath.Join(dest, binMarker), []byte(filepath.Base(e)+"\n"), 0o644)
			}
		}
		return errors.New("el zip no trae el ejecutable de Godot")
	}
	bins, _ := filepath.Glob(filepath.Join(dest, "Godot_v*"))
	var bin string
	for _, b := range bins {
		if fi, err := os.Stat(b); err == nil && fi.Mode().IsRegular() && !strings.HasSuffix(b, ".debugsymbols") {
			bin = b
			break
		}
	}
	if bin == "" {
		return errors.New("el zip no trae el binario de Godot")
	}
	if err := os.Chmod(bin, 0o755); err != nil {
		return err
	}
	os.Remove(filepath.Join(dest, "godot"))
	if mono {
		// el mono busca GodotSharp/ al lado de su nombre original
		return os.Symlink(filepath.Base(bin), filepath.Join(dest, "godot"))
	}
	return os.Rename(bin, filepath.Join(dest, "godot"))
}

func cmdRemove(name string) error {
	if name == "" {
		return errors.New("uso: godot-manager remove <version>")
	}
	bin, err := requireInstalled(name)
	if err != nil {
		return err
	}
	dir := filepath.Join(versionsDir, name)

	// hay que resolverlo antes de borrar el binario
	templates := templatesDirFor(bin)
	isDefault := defaultVersion() == name

	fmt.Printf("Se va a borrar %s (%s)\n", dir, humanSize(dirSize(dir)))
	if isDefault {
		fmt.Printf("Aviso: '%s' es la version default; va a quedar sin default.\n", name)
	}
	if !confirm(fmt.Sprintf("¿Borrar '%s'?", name)) {
		fmt.Println("Cancelado.")
		return nil
	}
	if err := os.RemoveAll(dir); err != nil {
		return err
	}
	if isDefault {
		clearDefault()
	}
	fmt.Printf("Borrada '%s'\n", name)

	if templates == "" {
		return nil
	}
	// otra version instalada puede usar la misma carpeta de templates
	for _, v := range installedVersions() {
		if b, ok := versionBinary(v); ok && templatesDirFor(b) == templates {
			fmt.Printf("Aviso: %s tambien usa %s\n", v, templates)
			break
		}
	}
	if confirm(fmt.Sprintf("¿Borrar tambien los export templates en %s (%s)?", templates, humanSize(dirSize(templates)))) {
		if err := os.RemoveAll(templates); err != nil {
			return err
		}
		fmt.Println("Templates borrados")
	}
	return nil
}

func usage(w io.Writer) {
	fmt.Fprintf(w, `Uso: godot-manager [--json] <comando> [args]

Comandos:
  list                              Lista versiones instaladas
  list-remote [stable|dev|latest]   Lista versiones disponibles en GitHub (todas, filtradas, o la ultima de cada una)
  install <ver> [--mono] [--debugsymbols] [--templates] [--platforms=<p>,...]
                                    Descarga, verifica checksum e instala una version oficial
                                    (--templates/--platforms agregan los export templates, como
                                    'templates'; --debugsymbols aplica al editor y a los templates)
  symbols <ver>                     Agrega los simbolos de debug a una version oficial instalada
                                    (>= 4.8-beta1, linux y windows)
  templates <ver> [--mono] [--platforms=<p>,...] [--debugsymbols[=<id|plataforma>,...|all]]
            [--debugsymbolsonly]
                                    Instala los export templates oficiales de una version y,
                                    opcionalmente, sus simbolos de debug (>= 4.8-beta1).
                                    --platforms: %s
                                      (default: todas; baja solo los archivos de las elegidas)
                                    --debugsymbols sin lista: los de --platforms, o
                                      %s
                                      Ids: linux_debug.arm64, windows_release_x86_64.exe,
                                      macos_debug.arm64, android_release...
                                    --debugsymbolsonly: no toca los templates, solo baja los
                                      simbolos de los ya instalados (todos, o los filtrados)
  add <nombre> <path> [--symlink]   Agrega un binario custom (build propio)
  remove <ver>                      Borra una version (y pregunta si borrar sus export templates)
  set <ver>                         Setea la version default global
  set-local <ver>                   Setea la version para el proyecto actual (.godot-version)
  which                             Muestra que binario usaria 'godot' en el directorio actual
  run [args...]                     Corre la version que corresponde al directorio actual (lo que hace 'godot')
  launch <ver> [args...]            Corre una version puntual sin cambiar la default
  version                           Muestra la version de godot-manager

Opciones:
  --json                            Salida en JSON para list, list-remote y which

Variables:
  GODOT_DIR                         Raiz de las versiones (ahora: %s)
  GITHUB_TOKEN                      Token opcional para la API de GitHub (sube el limite de pedidos)
`, strings.Join(templatePlatforms, " "), strings.Join(defaultTemplateSymbols(), ","), godotDir)
}
