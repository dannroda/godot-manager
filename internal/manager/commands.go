package manager

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
)

var Version = "dev"

// Comandos que con --json emiten eventos (uno por linea) en vez de un solo
// objeto.
var eventCommands = []string{"install", "templates", "symbols"}

func Main(args []string) int {
	// opciones globales, antes del comando
	asJSON, dir := false, ""
	var flagErr error
	for len(args) > 0 && flagErr == nil {
		if args[0] == "--json" {
			asJSON, args = true, args[1:]
			continue
		}
		rest, d, ok, err := takeDirFlag(args)
		if err != nil {
			flagErr = err
			break
		}
		if !ok {
			break
		}
		args, dir = rest, d
	}
	cmd := ""
	if len(args) > 0 {
		cmd, args = args[0], args[1:]
	}
	// --json tambien vale despues del comando en los que solo leen
	if cmd == "list" || cmd == "list-remote" || cmd == "which" || cmd == "plugins" {
		args, asJSON = jsonFlag(args, asJSON)
	}
	if asJSON {
		out.mode = modeJSON
		if slices.Contains(eventCommands, cmd) || (cmd == "self-update" && !slices.Contains(args, "--check")) {
			out.mode = modeEvents
		}
	}
	if flagErr != nil {
		out.fail(errf(codeInvalidArgs, "%v", flagErr))
		return 1
	}

	if runtime.GOOS == "windows" {
		cleanOldSelf()
	}
	res, err := dispatch(cmd, args, dir)
	if err != nil {
		out.fail(err)
		return 1
	}
	if res != nil {
		out.result(res)
	}
	return 0
}

func dispatch(cmd string, args []string, dir string) (map[string]any, error) {
	// which y set-local tambien aceptan --dir despues del comando; run y
	// launch no, porque sus argumentos son de Godot
	if cmd == "which" || cmd == "set-local" || cmd == "plugins" {
		var err error
		if args, dir, err = stripDirFlag(args, dir); err != nil {
			return nil, errf(codeInvalidArgs, "%v", err)
		}
	}
	if dir != "" {
		// la carpeta desde donde se resuelve .godot-version (y donde corre
		// Godot con run/launch): un proceso de Godot no puede elegir el
		// directorio de trabajo de sus hijos
		if fi, err := os.Stat(dir); err != nil || !fi.IsDir() {
			return nil, errf(codeInvalidArgs, "'%s' no es una carpeta", dir)
		}
		if err := os.Chdir(dir); err != nil {
			return nil, err
		}
	}
	if cmd == "remove" || cmd == "install" || cmd == "templates" || cmd == "plugins" || cmd == "self-update" {
		args = yesFlag(args)
	}
	if err := initPaths(); err != nil {
		return nil, err
	}
	arg := func(i int) string {
		if i < len(args) {
			return args[i]
		}
		return ""
	}

	switch cmd {
	case "list":
		return nil, cmdList()
	case "list-remote":
		return nil, cmdListRemote(arg(0))
	case "install":
		return cmdInstall(args)
	case "symbols":
		return cmdSymbols(arg(0))
	case "templates":
		return cmdTemplates(args)
	case "add":
		return cmdAdd(args)
	case "remove":
		return cmdRemove(args)
	case "set":
		return cmdSet(arg(0))
	case "set-local":
		if arg(0) == "--unset" {
			return cmdUnsetLocal()
		}
		return cmdSetLocal(arg(0))
	case "which":
		return nil, cmdWhich()
	case "run":
		return cmdRun(args)
	case "launch":
		return cmdLaunch(args)
	case "plugins":
		return cmdPlugins(args)
	case "self-update":
		return cmdSelfUpdate(args)
	case "version", "--version":
		fmt.Println(Version)
		return nil, nil
	case "-h", "--help", "help", "":
		usage(os.Stdout)
		return nil, nil
	}
	if out.isJSON() {
		return nil, errf(codeUnknownCommand, "comando desconocido '%s' (ver 'godot-manager help')", cmd)
	}
	usage(os.Stderr)
	return nil, errf(codeUnknownCommand, "comando desconocido '%s'", cmd)
}

type installedVersion struct {
	Name              string   `json:"name"`
	Path              string   `json:"path"`
	Default           bool     `json:"default"`
	Mono              bool     `json:"mono"`
	DebugSymbols      bool     `json:"debug_symbols"`
	Tag               string   `json:"tag"` // de la release, sin -mono; vacio si es custom
	Custom            bool     `json:"custom"`
	TemplatesDir      string   `json:"templates_dir"`
	TemplatePlatforms []string `json:"template_platforms"`
}

func cmdList() error {
	def := defaultVersion()
	list := []installedVersion{}
	for _, name := range installedVersions() {
		bin, ok := versionBinary(name)
		if !ok {
			continue
		}
		dir := filepath.Join(versionsDir, name)
		syms, _ := filepath.Glob(filepath.Join(dir, "*.debugsymbols"))
		tdir := officialTemplatesDir(name)
		platforms := []string{}
		if tdir != "" {
			platforms = installedPlatforms(tdir)
		}
		tag := versionTag(name)
		list = append(list, installedVersion{
			Name:              name,
			Path:              bin,
			Default:           name == def,
			Mono:              exists(filepath.Join(filepath.Dir(bin), "GodotSharp")),
			DebugSymbols:      len(syms) > 0,
			Tag:               tag,
			Custom:            tag == "",
			TemplatesDir:      tdir,
			TemplatePlatforms: platforms,
		})
	}
	if out.isJSON() {
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
	URL         string `json:"url"` // pagina de la release en GitHub
	// que trae para esta plataforma
	Editor        bool  `json:"editor"`
	Mono          bool  `json:"mono"`
	DebugSymbols  bool  `json:"debug_symbols"`
	Templates     bool  `json:"templates"`
	MonoTemplates bool  `json:"mono_templates"`
	EditorSize    int64 `json:"editor_size"`
	MonoSize      int64 `json:"mono_size"`
	TemplatesSize int64 `json:"templates_size"`
}

// Primer asset de names que tenga la release.
func firstAsset(r *release, names []string) *asset {
	for _, n := range names {
		if a := r.asset(n); a != nil {
			return a
		}
	}
	return nil
}

func describeRelease(r *release) remoteVersion {
	v := remoteVersion{Tag: r.TagName, Prerelease: r.Prerelease, PublishedAt: r.PublishedAt, URL: r.HTMLURL}
	if names, err := editorAssets(r.TagName, false); err == nil {
		if a := firstAsset(r, names); a != nil {
			v.Editor, v.EditorSize = true, a.Size
		}
	}
	if names, err := editorAssets(r.TagName, true); err == nil {
		if a := firstAsset(r, names); a != nil {
			v.Mono, v.MonoSize = true, a.Size
		}
	}
	if f, err := editorSymbolsFile(r.TagName, false); err == nil {
		v.DebugSymbols = r.asset(f+".zip") != nil
	}
	if a := r.asset(assetPrefix(r.TagName, false) + "export_templates.tpz"); a != nil {
		v.Templates, v.TemplatesSize = true, a.Size
	}
	v.MonoTemplates = r.asset(assetPrefix(r.TagName, true)+"export_templates.tpz") != nil
	return v
}

// Release de mayor version entre las que cumplen keep.
func newest(rs []release, keep func(*release) bool) string {
	best := ""
	for i := range rs {
		if keep(&rs[i]) && (best == "" || compareTags(rs[i].TagName, best) > 0) {
			best = rs[i].TagName
		}
	}
	return best
}

func cmdListRemote(filter string) error {
	rs, err := listReleases()
	if err != nil {
		return err
	}
	if filter == "latest" {
		stable := newest(rs, func(r *release) bool { return !r.Prerelease })
		dev := newest(rs, func(r *release) bool { return r.Prerelease })
		if out.isJSON() {
			return printJSON(map[string]string{"stable": stable, "dev": dev})
		}
		fmt.Println("Ultima estable: ", stable)
		fmt.Println("Ultima dev/pre-release:", dev)
		return nil
	}

	var title string
	keep := func(*release) bool { return true }
	switch filter {
	case "dev":
		title = "Dev snapshots / pre-releases (beta, rc, dev):"
		keep = func(r *release) bool { return r.Prerelease }
	case "stable":
		title = "Versiones estables:"
		keep = func(r *release) bool { return !r.Prerelease }
	default:
		title = "Todas las versiones (usa 'stable', 'dev' o 'latest' para filtrar):"
	}
	vs := []remoteVersion{}
	for i := range rs {
		if keep(&rs[i]) {
			vs = append(vs, describeRelease(&rs[i]))
		}
	}
	if out.isJSON() {
		return printJSON(vs)
	}
	fmt.Println(title)
	for _, v := range vs {
		fmt.Println(v.Tag)
	}
	return nil
}

func cmdSet(name string) (map[string]any, error) {
	bin, err := requireInstalled(name)
	if err != nil {
		return nil, err
	}
	if err := setDefault(name, bin); err != nil {
		return nil, err
	}
	out.step("Default seteado a %s", name)
	return map[string]any{"version": name, "path": bin}, nil
}

func cmdSetLocal(name string) (map[string]any, error) {
	if _, err := requireInstalled(name); err != nil {
		return nil, err
	}
	wd, err := os.Getwd()
	if err != nil {
		return nil, err
	}
	f := filepath.Join(wd, ".godot-version")
	if err := os.WriteFile(f, []byte(name+"\n"), 0o644); err != nil {
		return nil, err
	}
	out.step("Version local seteada a %s en %s", name, f)
	return map[string]any{"version": name, "file": f}, nil
}

// Borra el .godot-version de la carpeta actual: vuelve a usar la default (o
// el de una carpeta de mas arriba).
func cmdUnsetLocal() (map[string]any, error) {
	wd, err := os.Getwd()
	if err != nil {
		return nil, err
	}
	f := filepath.Join(wd, ".godot-version")
	if err := os.Remove(f); errors.Is(err, os.ErrNotExist) {
		out.step("No hay version local en %s", wd)
		return map[string]any{"file": f, "removed": false}, nil
	} else if err != nil {
		return nil, err
	}
	out.step("Version local quitada de %s", wd)
	return map[string]any{"file": f, "removed": true}, nil
}

func cmdWhich() error {
	r, err := resolve()
	if err != nil {
		return err
	}
	if out.isJSON() {
		return printJSON(r)
	}
	fmt.Println(r.Path)
	return nil
}

// --detach justo despues de run/launch: lanza Godot aparte y vuelve enseguida
// (para la UI). Sin --detach se reemplaza el proceso (en Windows, se espera).
func detachFlag(args []string) ([]string, bool) {
	if len(args) > 0 && args[0] == "--detach" {
		return args[1:], true
	}
	return args, false
}

func runBinary(version, bin string, args []string, detach bool) (map[string]any, error) {
	if !detach {
		return nil, launchError(bin, execBinary(bin, args))
	}
	pid, err := startDetached(bin, args)
	if err != nil {
		return nil, launchError(bin, err)
	}
	out.step("Lanzado %s (pid %d)", version, pid)
	return map[string]any{"version": version, "path": bin, "pid": pid}, nil
}

// Error de arranque con la causa sola ("no such file or directory"), sin el
// "fork/exec <path>:" que agrega Go.
func launchError(bin string, err error) error {
	if err == nil {
		return nil
	}
	cause := err
	var pe *os.PathError
	var ee *exec.Error
	switch {
	case errors.As(err, &pe):
		cause = pe.Err
	case errors.As(err, &ee):
		cause = ee.Err
	}
	return &cliError{
		Code:    codeLaunchFailed,
		Msg:     fmt.Sprintf("no se pudo ejecutar %s: %v", bin, cause),
		Details: map[string]any{"path": bin},
	}
}

func cmdRun(args []string) (map[string]any, error) {
	args, detach := detachFlag(args)
	r, err := resolve()
	if err != nil {
		return nil, err
	}
	return runBinary(r.Version, r.Path, args, detach)
}

func cmdLaunch(args []string) (map[string]any, error) {
	args, detach := detachFlag(args)
	if len(args) == 0 {
		return nil, errf(codeInvalidArgs, "uso: godot-manager launch [--detach] <version> [args...]")
	}
	bin, err := requireInstalled(args[0])
	if err != nil {
		return nil, err
	}
	return runBinary(args[0], bin, args[1:], detach)
}

func cmdAdd(args []string) (map[string]any, error) {
	var symlink, force bool
	var pos []string
	for _, a := range args {
		switch a {
		case "--symlink":
			symlink = true
		case "--force":
			force = true
		default:
			if strings.HasPrefix(a, "--") {
				return nil, errf(codeInvalidArgs, "opcion desconocida '%s'", a)
			}
			pos = append(pos, a)
		}
	}
	if len(pos) != 2 {
		return nil, errf(codeInvalidArgs, "uso: godot-manager add <nombre> <ruta-al-binario> [--symlink] [--force]")
	}
	name, src := pos[0], pos[1]
	if !validName(name) {
		return nil, errf(codeInvalidArgs, "nombre invalido '%s'", name)
	}
	if !isExecutable(src) {
		return nil, errf(codeInvalidArgs, "%s no existe o no es ejecutable", src)
	}
	dir := filepath.Join(versionsDir, name)
	if exists(dir) {
		if !force {
			return nil, &cliError{
				Code:    codeAlreadyInstalled,
				Msg:     fmt.Sprintf("ya hay una version '%s' (usa --force para reemplazarla)", name),
				Details: map[string]any{"version": name},
			}
		}
		// reemplazo completo: no quedan restos de la anterior (otro binario,
		// simbolos, el _console.exe de una oficial)
		if defaultVersion() == name {
			defer func() {
				if bin, ok := versionBinary(name); ok {
					setDefault(name, bin)
				}
			}()
		}
		if err := os.RemoveAll(dir); err != nil {
			return nil, err
		}
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	os.Remove(filepath.Join(dir, binMarker))
	if err := os.WriteFile(filepath.Join(dir, customMarker), []byte("add\n"), 0o644); err != nil {
		return nil, err
	}

	if symlink {
		abs, err := filepath.Abs(src)
		if err != nil {
			return nil, err
		}
		if abs, err = filepath.EvalSymlinks(abs); err != nil {
			return nil, err
		}
		if runtime.GOOS == "windows" {
			err = os.WriteFile(filepath.Join(dir, binMarker), []byte(abs+"\n"), 0o644)
		} else {
			link := filepath.Join(dir, "godot")
			os.Remove(link)
			err = os.Symlink(abs, link)
		}
		if err != nil {
			return nil, err
		}
		out.step("Agregado '%s' como symlink a %s", name, src)
	} else {
		dst := filepath.Join(dir, "godot")
		if runtime.GOOS == "windows" {
			dst += ".exe"
		}
		if err := copyFile(src, dst, 0o755); err != nil {
			return nil, err
		}
		out.step("Agregado '%s' (copiado desde %s)", name, src)
	}
	bin, _ := versionBinary(name)
	return map[string]any{"version": name, "path": bin}, nil
}

// Desde 4.8-beta1 cada release trae simbolos de debug aparte para el editor
// (linux y windows). El binario oficial los referencia por nombre via
// .gnu_debuglink, asi que alcanza con dejarlos al lado del binario: gdb y
// addr2line los encuentran solos. No estan en el manifest, se verifican
// contra el digest sha256 que expone la API de GitHub para cada asset.
func cmdSymbols(name string) (map[string]any, error) {
	if name == "" {
		return nil, errf(codeInvalidArgs, "uso: godot-manager symbols <version>[-mono]")
	}
	bin, err := requireInstalled(name)
	if err != nil {
		return nil, err
	}
	ver, mono := strings.CutSuffix(name, "-mono")
	symfile, err := editorSymbolsFile(ver, mono)
	if err != nil {
		return nil, errf(codeNotAvailable, "%v", err)
	}
	dir := filepath.Dir(bin)
	if !strings.HasPrefix(dir, versionsDir) {
		dir = filepath.Join(versionsDir, name)
	}
	file := filepath.Join(dir, symfile)
	res := map[string]any{"version": name, "file": file}
	if exists(file) {
		out.step("'%s' ya tiene los simbolos de debug.", name)
		return res, nil
	}

	missing := errf(codeNotAvailable, "la release '%s' no tiene %s.zip (existen desde 4.8-beta1, y solo para builds oficiales)", ver, symfile)
	rel, err := getRelease(ver)
	if err != nil {
		if code, _ := errorInfo(err); code == codeNoRelease {
			return nil, missing
		}
		return nil, err
	}
	a := rel.asset(symfile + ".zip")
	if a == nil {
		return nil, missing
	}

	tmp, err := makeTemp(versionsDir)
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(tmp)
	out.step("Simbolos de debug: %s de descarga, ~3x en disco", humanSize(a.Size))
	zipPath := filepath.Join(tmp, "symbols.zip")
	if err := downloadVerified(githubDL+"/"+ver+"/"+a.Name, zipPath, "sha256", a.sha256()); err != nil {
		return nil, err
	}
	if err := extractZip(zipPath, dir, func(n string) bool { return n == symfile }); err != nil {
		return nil, err
	}
	if !exists(file) {
		return nil, errf(codeNotAvailable, "el zip no trae %s", symfile)
	}
	out.step("Simbolos de debug instalados en %s", file)
	return res, nil
}

func cmdInstall(args []string) (map[string]any, error) {
	if len(args) == 0 {
		return nil, errf(codeInvalidArgs, "uso: godot-manager install <version> [--mono] [--debugsymbols] [--templates] [--platforms=<p>,...] [--yes]")
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
			return nil, errf(codeInvalidArgs, "opcion desconocida '%s'", opt)
		}
	}

	destName := ver
	if mono {
		destName += "-mono"
	}
	if !validName(destName) {
		return nil, errf(codeInvalidArgs, "version invalida '%s'", ver)
	}
	if _, ok := versionBinary(destName); ok {
		out.step("'%s' ya esta instalada.", destName)
	} else if err := installEditor(ver, mono, filepath.Join(versionsDir, destName)); err != nil {
		return nil, err
	}
	bin, _ := versionBinary(destName)
	res := map[string]any{"version": destName, "path": bin}

	if symbols {
		if _, err := cmdSymbols(destName); err != nil {
			return nil, err
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
		t, err := cmdTemplates(targs)
		if err != nil {
			return nil, err
		}
		res["templates_dir"] = t["templates_dir"]
	}
	return res, nil
}

func installEditor(ver string, mono bool, dest string) error {
	rel, err := getRelease(ver)
	if err != nil {
		return err
	}
	candidates, err := editorAssets(ver, mono)
	if err != nil {
		return errf(codeNoBuild, "%v", err)
	}
	a := firstAsset(rel, candidates)
	if a == nil {
		return errf(codeNoBuild, "la release '%s' no tiene build para esta plataforma (%s)", ver, strings.Join(candidates, ", "))
	}
	algo, sum := "sha512", manifestChecksum(ver, a.Name)
	if sum == "" {
		algo, sum = "sha256", a.sha256()
	}

	tmp, err := makeTemp(versionsDir)
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	zipPath := filepath.Join(tmp, "godot.zip")
	if err := downloadVerified(githubDL+"/"+ver+"/"+a.Name, zipPath, algo, sum); err != nil {
		return err
	}
	out.step("Extrayendo...")
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
	os.Remove(filepath.Join(dest, customMarker))
	if err := setupBinary(dest, mono); err != nil {
		os.RemoveAll(dest)
		return err
	}
	out.step("Instalado en %s", dest)
	return nil
}

// Deja el binario de una version recien extraida donde versionBinary lo busca.
func setupBinary(dest string, mono bool) error {
	if runtime.GOOS == "windows" {
		exes, _ := filepath.Glob(filepath.Join(dest, "Godot_v*.exe"))
		for _, e := range exes {
			if !strings.HasSuffix(e, "_console.exe") {
				return os.WriteFile(filepath.Join(dest, binMarker), []byte(filepath.Base(e)+"\n"), 0o644)
			}
		}
		return errf(codeNoBuild, "el zip no trae el ejecutable de Godot")
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
		return errf(codeNoBuild, "el zip no trae el binario de Godot")
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

// remove <ver> [--yes] [--templates]: sin --yes pregunta por la terminal (y
// sin terminal falla); con --yes los templates solo se borran con --templates.
func cmdRemove(args []string) (map[string]any, error) {
	name, withTemplates := "", false
	for _, a := range args {
		switch {
		case a == "--templates":
			withTemplates = true
		case strings.HasPrefix(a, "-"):
			return nil, errf(codeInvalidArgs, "opcion desconocida '%s'", a)
		case name == "":
			name = a
		default:
			return nil, errf(codeInvalidArgs, "sobra '%s'", a)
		}
	}
	if name == "" {
		return nil, errf(codeInvalidArgs, "uso: godot-manager remove <version> [--yes] [--templates]")
	}
	bin, err := requireInstalled(name)
	if err != nil {
		return nil, err
	}
	dir := filepath.Join(versionsDir, name)

	// hay que resolverlo antes de borrar el binario
	templates := officialTemplatesDir(name)
	if templates == "" {
		templates = templatesDirFor(bin)
	}
	isDefault := defaultVersion() == name

	out.step("Se va a borrar %s (%s)", dir, humanSize(dirSize(dir)))
	if isDefault {
		out.warn("'%s' es la version default; va a quedar sin default.", name)
	}
	ok, err := confirm(fmt.Sprintf("¿Borrar '%s'?", name))
	if err != nil {
		return nil, err
	}
	if !ok {
		out.step("Cancelado.")
		return nil, nil
	}
	if err := os.RemoveAll(dir); err != nil {
		return nil, err
	}
	if isDefault {
		clearDefault()
	}
	out.step("Borrada '%s'", name)
	res := map[string]any{"version": name, "removed_templates": ""}

	if templates == "" {
		return res, nil
	}
	// otra version instalada puede usar la misma carpeta de templates
	for _, v := range installedVersions() {
		if officialTemplatesDir(v) == templates {
			out.warn("%s tambien usa %s", v, templates)
			break
		}
	}
	del := withTemplates
	if !del && !assumeYes {
		if del, err = confirm(fmt.Sprintf("¿Borrar tambien los export templates en %s (%s)?", templates, humanSize(dirSize(templates)))); err != nil {
			return nil, err
		}
	}
	if del {
		if err := os.RemoveAll(templates); err != nil {
			return nil, err
		}
		out.step("Templates borrados")
		res["removed_templates"] = templates
	}
	return res, nil
}

func usage(w io.Writer) {
	fmt.Fprintf(w, `Uso: godot-manager [--json] [--dir <carpeta>] <comando> [args]

Comandos:
  list                              Lista versiones instaladas
  list-remote [stable|dev|latest]   Lista versiones disponibles en GitHub (todas, filtradas, o la ultima de cada una)
  install <ver> [--mono] [--debugsymbols] [--templates] [--platforms=<p>,...] [--yes]
                                    Descarga, verifica checksum e instala una version oficial
                                    (--templates/--platforms agregan los export templates, como
                                    'templates'; --debugsymbols aplica al editor y a los templates)
  symbols <ver>                     Agrega los simbolos de debug a una version oficial instalada
                                    (>= 4.8-beta1, linux y windows)
  templates <ver> [--mono] [--platforms=<p>,...] [--debugsymbols[=<id|plataforma>,...|all]]
            [--debugsymbolsonly] [--yes]
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
  add <nombre> <path> [--symlink] [--force]
                                    Agrega un binario custom (build propio). Si el nombre
                                    ya existe falla, salvo con --force (lo reemplaza)
  remove <ver> [--yes] [--templates]
                                    Borra una version. Pregunta si borrar sus export templates;
                                    con --yes no pregunta y los borra solo con --templates
  set <ver>                         Setea la version default global
  set-local <ver>                   Setea la version para el proyecto actual (.godot-version)
  set-local --unset                 Quita la version del proyecto actual (vuelve a la default)
  which                             Muestra que binario usaria 'godot' en el directorio actual
  run [--detach] [args...]          Corre la version que corresponde al directorio actual (lo que hace 'godot')
  launch [--detach] <ver> [args...] Corre una version puntual sin cambiar la default
                                    (--detach: la lanza aparte, sin consola, y vuelve enseguida)
  plugins [list]                    Lista los plugins del proyecto actual (addons/*/plugin.cfg),
                                    cuales estan activos y si les falta algo
  plugins enable|disable <plugin>   Activa o desactiva un plugin en project.godot, sin abrir el
                                    editor (sirve si un plugin roto no lo deja abrir)
  plugins remove <plugin> [--yes]   Lo desactiva y borra su carpeta de addons/
  self-update [--check] [--yes]     Actualiza godot-manager (y la interfaz, si esta en la misma
                                    carpeta) a la ultima release; --check solo dice si hay una
                                    nueva (con --json, un objeto)
  version                           Muestra la version de godot-manager

Opciones:
  --json                            Salida en JSON en stdout (ver abajo)
  --dir <carpeta>, -C <carpeta>     Usa esa carpeta como directorio actual (which, set-local,
                                    run, launch, plugins); en which, set-local y plugins va despues
                                    del comando
  --yes, -y                         Confirma sin preguntar (remove, install, templates,
                                    plugins remove, self-update). Sin terminal y sin --yes, lo
                                    que pide confirmacion falla

Salida con --json:
  list, list-remote, which,         El JSON del listado o de la version que corresponde
  plugins, self-update --check
  install, templates, symbols,      Un objeto por linea: {"event":"step","message"},
  self-update                       {"event":"download","file","done","total"},
                                    {"event":"warn","message"}; la ultima linea es
                                    {"event":"done",...} o {"event":"error","code","message"}
  los demas                         {"ok":true,...} o {"error":{"code","message"}}
  Codigos de error: not_installed, no_default, no_release, no_build_for_platform,
  not_available, rate_limited, network, checksum, invalid_args, unknown_command,
  needs_confirmation, bad_token, already_installed, launch_failed, not_a_project,
  no_plugin, cannot_self_update, internal

Variables:
  GODOT_DIR                         Raiz de las versiones (ahora: %s)
  GITHUB_TOKEN                      Token opcional para la API de GitHub (sube el limite de pedidos)
`, strings.Join(templatePlatforms, " "), strings.Join(defaultTemplateSymbols(), ","), godotDir)
}
