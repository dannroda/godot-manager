package manager

import (
	"archive/tar"
	"archive/zip"
	"bufio"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
)

// self-update: actualiza godot-manager desde sus propias releases de GitHub.
// Baja el archivo de este sistema (los mismos que arma el workflow de
// release), lo verifica con SHA256SUMS y reemplaza los binarios de la carpeta
// donde esta instalado. Solo toca archivos que ya estan en esa carpeta (mas
// godot-manager y godot), asi una instalacion sin la interfaz sigue sin ella.
//
// Los assets se bajan por la API (releases/assets/<id> con Accept
// octet-stream): asi funciona tambien con el repo privado y GITHUB_TOKEN.

const selfRepo = "dannroda/godot-manager"

var (
	selfAPI = "https://api.github.com/repos/" + selfRepo
	// Ruta del ejecutable que se actualiza (los tests la cambian).
	selfExecutable = func() (string, error) {
		p, err := os.Executable()
		if err != nil {
			return "", err
		}
		return filepath.EvalSymlinks(p)
	}
)

type updateInfo struct {
	Current         string `json:"current"`
	Latest          string `json:"latest"`
	UpdateAvailable bool   `json:"update_available"`
	CanUpdate       bool   `json:"can_update"`
	Reason          string `json:"reason"` // por que no se puede (si can_update es false)
	URL             string `json:"url"`    // pagina de la release
	Asset           string `json:"asset"`
	Dir             string `json:"dir"` // carpeta que se actualiza

	rel *release
}

func cmdSelfUpdate(args []string) (map[string]any, error) {
	check := false
	for _, a := range args {
		switch a {
		case "--check":
			check = true
		default:
			return nil, errf(codeInvalidArgs, "opcion desconocida '%s' (uso: godot-manager self-update [--check] [--yes])", a)
		}
	}
	info, err := checkUpdate()
	if err != nil {
		return nil, err
	}
	if check {
		if out.isJSON() {
			return nil, printJSON(info)
		}
		switch {
		case !info.UpdateAvailable:
			fmt.Printf("godot-manager %s es la ultima version (%s).\n", info.Current, info.Latest)
		case info.CanUpdate:
			fmt.Printf("Hay una version nueva: %s (tenes %s). Actualiza con 'godot-manager self-update'.\n", info.Latest, info.Current)
		default:
			fmt.Printf("Hay una version nueva: %s (tenes %s), pero %s.\n", info.Latest, info.Current, info.Reason)
		}
		return nil, nil
	}
	if !info.UpdateAvailable {
		out.step("godot-manager %s es la ultima version", info.Current)
		return map[string]any{"updated": false, "version": info.Current}, nil
	}
	if !info.CanUpdate {
		return nil, errf(codeCannotSelfUpdate, "no se puede actualizar solo: %s", info.Reason)
	}
	out.step("Actualizando godot-manager %s a %s en %s", info.Current, info.Latest, info.Dir)
	ok, err := confirm(fmt.Sprintf("¿Actualizar a %s?", info.Latest))
	if err != nil {
		return nil, err
	}
	if !ok {
		out.step("Cancelado.")
		return nil, nil
	}
	replaced, err := applyUpdate(info)
	if err != nil {
		return nil, err
	}
	out.step("Actualizado a %s", info.Latest)
	return map[string]any{"updated": true, "from": info.Current, "version": info.Latest, "replaced": replaced}, nil
}

func checkUpdate() (*updateInfo, error) {
	info := &updateInfo{Current: Version}
	var rel release
	_, err := getJSON(selfAPI+"/releases/latest", &rel)
	if errors.Is(err, errNotFound) {
		msg := "no hay releases publicadas de " + selfRepo
		if os.Getenv("GITHUB_TOKEN") == "" {
			msg += " (si el repo es privado, defini GITHUB_TOKEN)"
		}
		return nil, errf(codeNoRelease, "%s", msg)
	}
	if err != nil {
		return nil, err
	}
	info.rel = &rel
	info.Latest = strings.TrimPrefix(rel.TagName, "v")
	info.URL = rel.HTMLURL
	info.UpdateAvailable = isNewerVersion(info.Latest, info.Current)

	info.Asset = selfAssetName(runtime.GOOS, runtime.GOARCH)
	exe, err := selfExecutable()
	if err != nil {
		info.Reason = fmt.Sprintf("no se encontro el ejecutable (%v)", err)
		return info, nil
	}
	info.Dir = filepath.Dir(exe)
	switch {
	case !versionCore.MatchString(strings.TrimPrefix(info.Current, "v")):
		info.Reason = fmt.Sprintf("esta es una version de desarrollo (%s)", info.Current)
	case packageManager(runtime.GOOS, info.Dir) != "":
		info.Reason = fmt.Sprintf("lo instalo %s en %s: actualizalo por ahi", packageManager(runtime.GOOS, info.Dir), info.Dir)
	case rel.asset(info.Asset) == nil:
		info.Reason = fmt.Sprintf("la release %s no trae %s", rel.TagName, info.Asset)
	case !dirWritable(info.Dir):
		info.Reason = fmt.Sprintf("no se puede escribir en %s", info.Dir)
	default:
		info.CanUpdate = true
	}
	return info, nil
}

// Nombre del archivo de la release para un sistema (como en release.yml).
func selfAssetName(goos, goarch string) string {
	if goos == "windows" {
		return "godot-manager-windows-" + goarch + ".zip"
	}
	return "godot-manager-" + goos + "-" + goarch + ".tar.gz"
}

// Gestor de paquetes que instalo la carpeta, o "": el paquete de Arch va a
// /usr/bin; Scoop, a scoop\apps\<app>\<version>; Homebrew, a su Cellar.
func packageManager(goos, dir string) string {
	if goos == "windows" {
		if strings.Contains(strings.ToLower(strings.ReplaceAll(dir, `\`, "/")), "/scoop/apps/") {
			return "Scoop"
		}
		return ""
	}
	switch {
	case strings.Contains(dir, "/Cellar/") || strings.HasPrefix(dir, "/opt/homebrew/"):
		return "Homebrew"
	case dir == "/usr/bin" || dir == "/bin" || dir == "/usr/sbin" ||
		strings.HasPrefix(dir, "/usr/lib/") || strings.HasPrefix(dir, "/nix/store/"):
		return "el gestor de paquetes"
	}
	return ""
}

func dirWritable(dir string) bool {
	f, err := os.CreateTemp(dir, ".godot-manager-w.*")
	if err != nil {
		return false
	}
	f.Close()
	os.Remove(f.Name())
	return true
}

var versionCore = regexp.MustCompile(`^(\d+)\.(\d+)(?:\.(\d+))?(.*)$`)

// Si latest es mas nueva que current. Compara mayor.menor.parche; con el
// mismo numero, una current con sufijo -alpha/-beta/-rc es mas vieja. Un
// sufijo de git describe (2.2.0-3-gabc123) es posterior a 2.2.0: no se
// ofrece volver atras. Una current sin numero (dev) nunca se actualiza.
func isNewerVersion(latest, current string) bool {
	l := versionCore.FindStringSubmatch(strings.TrimPrefix(latest, "v"))
	c := versionCore.FindStringSubmatch(strings.TrimPrefix(current, "v"))
	if l == nil || c == nil {
		return false
	}
	for i := 1; i <= 3; i++ {
		a, _ := strconv.Atoi(l[i])
		b, _ := strconv.Atoi(c[i])
		if a != b {
			return a > b
		}
	}
	pre := regexp.MustCompile(`^-(alpha|beta|rc|dev)`)
	return l[4] == "" && pre.MatchString(c[4])
}

// Los archivos de la carpeta que se reemplazan, si estan en el paquete.
func selfFiles(goos string) []string {
	if goos == "windows" {
		return []string{"godot-manager.exe", "godot.exe", "godot-manager-ui.exe", "LICENSE", "README.md", "README.es.md"}
	}
	return []string{"godot-manager", "godot", "godot-manager-ui.x86_64", "godot-manager-ui.arm64", "LICENSE", "README.md", "README.es.md"}
}

func applyUpdate(info *updateInfo) ([]string, error) {
	a := info.rel.asset(info.Asset)
	tmp, err := makeTemp(info.Dir)
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(tmp)

	expected := a.sha256()
	if expected == "" {
		if expected, err = sumFromRelease(info.rel, info.Asset); err != nil {
			return nil, err
		}
	}
	archive := filepath.Join(tmp, info.Asset)
	if err := downloadAsset(a, archive, expected); err != nil {
		return nil, err
	}

	// Del paquete solo se sacan estos nombres (sin importar la carpeta de
	// adentro), asi un archivo raro no puede escribir fuera de tmp.
	exeName := "godot-manager"
	if runtime.GOOS == "windows" {
		exeName += ".exe"
	}
	wanted := map[string]bool{}
	for _, f := range selfFiles(runtime.GOOS) {
		if f == exeName || f == strings.Replace(exeName, "godot-manager", "godot", 1) {
			wanted[f] = true
			continue
		}
		if _, err := os.Stat(filepath.Join(info.Dir, f)); err == nil {
			wanted[f] = true
		}
	}
	newDir := filepath.Join(tmp, "new")
	if err := os.Mkdir(newDir, 0o755); err != nil {
		return nil, err
	}
	got, err := extractSelf(archive, newDir, wanted)
	if err != nil {
		return nil, err
	}
	if !got[exeName] {
		return nil, errf(codeInternal, "%s no trae %s", info.Asset, exeName)
	}
	return replaceFiles(info.Dir, newDir, got)
}

// sha256 de name en el SHA256SUMS de la release.
func sumFromRelease(rel *release, name string) (string, error) {
	sums := rel.asset("SHA256SUMS")
	if sums == nil {
		return "", errf(codeChecksum, "la release %s no trae SHA256SUMS ni el digest de %s", rel.TagName, name)
	}
	resp, err := assetGet(sums)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	sc := bufio.NewScanner(resp.Body)
	for sc.Scan() {
		f := strings.Fields(sc.Text())
		if len(f) == 2 && strings.TrimPrefix(f[1], "*") == name {
			return f[0], nil
		}
	}
	return "", errf(codeChecksum, "SHA256SUMS no tiene %s", name)
}

// GET de un asset por la API: la API redirige a la descarga (y Go no manda
// el token al otro host).
func assetGet(a *asset) (*http.Response, error) {
	u := a.URL
	if u == "" {
		return nil, errf(codeInternal, "el asset %s no tiene url", a.Name)
	}
	req, err := newRequest("GET", u)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/octet-stream")
	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, errf(codeNetwork, "no se pudo descargar %s: %v", a.Name, err)
	}
	if resp.StatusCode != http.StatusOK {
		resp.Body.Close()
		return nil, errf(codeNetwork, "no se pudo descargar %s (HTTP %d)", a.Name, resp.StatusCode)
	}
	return resp, nil
}

func downloadAsset(a *asset, dest, sha string) error {
	out.step("Descargando %s...", a.Name)
	resp, err := assetGet(a)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	f, err := os.Create(dest)
	if err != nil {
		return err
	}
	h := sha256.New()
	total := resp.ContentLength
	if total <= 0 {
		total = a.Size
	}
	p := newProgress(total)
	p.label = a.Name
	_, err = io.Copy(io.MultiWriter(f, h, p), resp.Body)
	p.finish()
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		return errf(codeNetwork, "descarga interrumpida: %v", err)
	}
	if got := hex.EncodeToString(h.Sum(nil)); !strings.EqualFold(got, sha) {
		return errf(codeChecksum, "el checksum de %s no coincide\n  esperado: %s\n  obtenido: %s", a.Name, sha, got)
	}
	out.step("Checksum verificado OK")
	return nil
}

// Extrae de un .tar.gz o .zip los archivos cuyo nombre (sin carpeta) esta en
// wanted. Devuelve los que encontro.
func extractSelf(archive, dest string, wanted map[string]bool) (map[string]bool, error) {
	got := map[string]bool{}
	write := func(name string, mode os.FileMode, r io.Reader) error {
		base := path.Base(strings.ReplaceAll(name, `\`, "/"))
		if !wanted[base] || got[base] {
			return nil
		}
		perm := os.FileMode(0o644)
		if mode&0o111 != 0 {
			perm = 0o755
		}
		f, err := os.OpenFile(filepath.Join(dest, base), os.O_CREATE|os.O_WRONLY|os.O_TRUNC, perm)
		if err != nil {
			return err
		}
		if _, err := io.Copy(f, r); err != nil {
			f.Close()
			return err
		}
		got[base] = true
		return f.Close()
	}
	if strings.HasSuffix(archive, ".zip") {
		zr, err := zip.OpenReader(archive)
		if err != nil {
			return nil, fmt.Errorf("zip invalido: %w", err)
		}
		defer zr.Close()
		for _, f := range zr.File {
			if f.Mode().IsDir() {
				continue
			}
			rc, err := f.Open()
			if err != nil {
				return nil, err
			}
			mode := f.Mode()
			if strings.HasSuffix(f.Name, ".exe") {
				mode |= 0o111
			}
			err = write(f.Name, mode, rc)
			rc.Close()
			if err != nil {
				return nil, err
			}
		}
		return got, nil
	}
	file, err := os.Open(archive)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	gz, err := gzip.NewReader(file)
	if err != nil {
		return nil, fmt.Errorf("tar.gz invalido: %w", err)
	}
	tr := tar.NewReader(gz)
	for {
		h, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("tar.gz invalido: %w", err)
		}
		if h.Typeflag != tar.TypeReg {
			continue
		}
		if err := write(h.Name, os.FileMode(h.Mode), tr); err != nil {
			return nil, err
		}
	}
	return got, nil
}

// Pone cada archivo nuevo en dir. El viejo pasa a <nombre>.old (un .exe que
// esta corriendo se puede renombrar pero no borrar) y despues se intenta
// borrar; si algo falla a mitad, vuelve todo como estaba.
func replaceFiles(dir, newDir string, files map[string]bool) ([]string, error) {
	var done []string
	rollback := func() {
		for _, name := range done {
			target := filepath.Join(dir, name)
			os.Remove(target)
			os.Rename(target+".old", target)
		}
	}
	for _, name := range selfFiles(runtime.GOOS) {
		if !files[name] {
			continue
		}
		target := filepath.Join(dir, name)
		old := target + ".old"
		os.Remove(old)
		hadOld := false
		if _, err := os.Stat(target); err == nil {
			if err := os.Rename(target, old); err != nil {
				rollback()
				return nil, fmt.Errorf("no se pudo mover %s: %w", target, err)
			}
			hadOld = true
		}
		if err := os.Rename(filepath.Join(newDir, name), target); err != nil {
			if hadOld {
				os.Rename(old, target)
			}
			rollback()
			return nil, fmt.Errorf("no se pudo escribir %s: %w", target, err)
		}
		done = append(done, name)
	}
	for _, name := range done {
		os.Remove(filepath.Join(dir, name+".old")) // en Windows falla si corre: lo borra cleanOldSelf
	}
	return done, nil
}

// Borra los .old que dejo un self-update en Windows (no se pudieron borrar
// porque estaban corriendo). Se llama al arrancar; no falla nunca.
func cleanOldSelf() {
	exe, err := selfExecutable()
	if err != nil {
		return
	}
	dir := filepath.Dir(exe)
	for _, name := range selfFiles(runtime.GOOS) {
		os.Remove(filepath.Join(dir, name+".old"))
	}
}
