package manager

import (
	"bufio"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"godot-manager/pluginkit"
)

// La librería de plugins (pluginkit/, en GDScript) es la misma que usan addons como godot-agent
// desde el editor. Acá va adentro del binario: se escribe una vez en $GODOT_DIR/pluginkit/<hash>/
// (con un project.godot propio, así Godot no toca el proyecto del usuario) y se corre con un
// Godot instalado, sin ventana. Avisa el progreso por stdout (`@pk {...}`) y deja el resultado en
// un archivo JSON.

// Versión de Godot más vieja con la que corre la librería.
var kitMinGodot = [2]int{4, 2}

const kitProgressPrefix = "@pk "

// Carpeta con la librería, escrita si hace falta. Borra las de versiones anteriores.
func kitDir() (string, error) {
	files, err := fs.ReadDir(pluginkit.Files, ".")
	if err != nil {
		return "", err
	}
	h := sha256.New()
	for _, f := range files {
		data, err := fs.ReadFile(pluginkit.Files, f.Name())
		if err != nil {
			return "", err
		}
		fmt.Fprintf(h, "%s\x00%d\x00", f.Name(), len(data))
		h.Write(data)
	}
	hash := hex.EncodeToString(h.Sum(nil))[:12]
	parent := filepath.Join(godotDir, "pluginkit")
	dir := filepath.Join(parent, hash)
	if exists(filepath.Join(dir, "cli.gd")) {
		return dir, nil
	}
	tmp, err := makeTemp(parent)
	if err != nil {
		return "", err
	}
	defer os.RemoveAll(tmp)
	for _, f := range files {
		data, _ := fs.ReadFile(pluginkit.Files, f.Name())
		if err := os.WriteFile(filepath.Join(tmp, f.Name()), data, 0o644); err != nil {
			return "", err
		}
	}
	os.Remove(filepath.Join(tmp, tempPID))
	if err := os.Rename(tmp, dir); err != nil && !exists(filepath.Join(dir, "cli.gd")) {
		return "", err
	}
	ents, _ := os.ReadDir(parent)
	for _, e := range ents {
		if e.IsDir() && e.Name() != hash && !strings.HasPrefix(e.Name(), ".") {
			os.RemoveAll(filepath.Join(parent, e.Name()))
		}
	}
	return dir, nil
}

// Un Godot instalado que pueda correr la librería: la default si sirve, si no la más nueva.
func kitGodot() (string, error) {
	vs := installedVersions()
	sort.Slice(vs, func(i, j int) bool { return compareTags(versionTag(vs[i]), versionTag(vs[j])) > 0 })
	if d := defaultVersion(); d != "" {
		vs = append([]string{d}, vs...)
	}
	for _, v := range vs {
		k, ok := parseTag(versionTag(v))
		if !ok || k[0] < kitMinGodot[0] || (k[0] == kitMinGodot[0] && k[1] < kitMinGodot[1]) {
			continue
		}
		if bin, ok := versionBinary(v); ok {
			return bin, nil
		}
	}
	return "", errf(codeNotInstalled, "para manejar plugins hace falta una versión oficial de Godot %d.%d o más nueva instalada (por ejemplo: godot-manager install 4.5)", kitMinGodot[0], kitMinGodot[1])
}

var featuresRe = regexp.MustCompile(`"(\d+\.\d+(?:\.\d+)?)"`)

// La versión de Godot del proyecto, para elegir plugins que anden con ella: su .godot-version o,
// si no tiene, la de config/features de project.godot ("4.5"). "" si no se sabe.
func projectGodot(proj string) string {
	if v := projectVersion(proj); v != "" {
		return v
	}
	data, err := os.ReadFile(filepath.Join(proj, "project.godot"))
	if err != nil {
		return ""
	}
	features := parseCfg(string(data))["application"]["config/features"]
	if m := featuresRe.FindStringSubmatch(features); m != nil {
		return m[1]
	}
	return ""
}

type kitRun struct {
	proj  string
	godot string // versión de Godot del proyecto
	force bool
}

// Corre una operación de la librería y devuelve su resultado; si la librería contesta un error, lo
// devuelve como cliError en castellano.
func (k kitRun) call(args ...string) (map[string]any, error) {
	dir, err := kitDir()
	if err != nil {
		return nil, err
	}
	bin, err := kitGodot()
	if err != nil {
		return nil, err
	}
	tmp, err := makeTemp(filepath.Join(godotDir, "pluginkit"))
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(tmp)
	outFile := filepath.Join(tmp, "result.json")
	full := append([]string{"--headless", "--path", dir, "--script", "res://cli.gd", "--"}, args...)
	full = append(full, "--project", k.proj, "--out", outFile, "--temp", filepath.Join(tmp, "dl"), "--godot", k.godot)
	if k.force {
		full = append(full, "--force")
	}
	cmd := exec.Command(consoleBinary(bin), full...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	if err := cmd.Start(); err != nil {
		return nil, launchError(bin, err)
	}
	sc := bufio.NewScanner(stdout)
	sc.Buffer(make([]byte, 64*1024), 1<<20)
	for sc.Scan() {
		if line, ok := strings.CutPrefix(sc.Text(), kitProgressPrefix); ok {
			var ev map[string]any
			if json.Unmarshal([]byte(line), &ev) == nil {
				kitProgress(ev)
			}
		}
	}
	cmd.Wait()
	data, err := os.ReadFile(outFile)
	if err != nil {
		msg := strings.TrimSpace(stderr.String())
		if lines := strings.Split(msg, "\n"); len(lines) > 8 {
			msg = strings.Join(lines[len(lines)-8:], "\n")
		}
		return nil, fmt.Errorf("la librería de plugins no terminó (con %s): %s", bin, msg)
	}
	var res map[string]any
	if err := json.Unmarshal(data, &res); err != nil {
		return nil, fmt.Errorf("la librería de plugins devolvió algo que no es JSON: %v", err)
	}
	if code, ok := res["error"].(string); ok {
		details, _ := res["details"].(map[string]any)
		return nil, kitError(code, details)
	}
	return res, nil
}

func kitProgress(ev map[string]any) {
	name, version := str(ev["name"]), str(ev["version"])
	switch ev["progress"] {
	case "check":
		out.step("Revisando %s", name)
	case "download":
		out.step("Bajando %s %s", name, version)
	case "install":
		out.step("Instalando %s %s (%d archivos)", name, version, int(num(ev["files"])))
	case "remove":
		out.step("Borrando %s", name)
	}
}

// Los errores de la librería, en castellano y con el código que ve la UI.
func kitError(code string, d map[string]any) error {
	if d == nil {
		d = map[string]any{}
	}
	name, version, source := str(d["name"]), str(d["version"]), str(d["source"])
	what := name
	if what == "" {
		what = source
	}
	var c, msg string
	switch code {
	case "invalid_source":
		c, msg = codeInvalidArgs, fmt.Sprintf("'%s' no es una fuente válida: usá store:publisher/slug, github:owner/repo o la URL de una de esas páginas", source)
	case "usage":
		c, msg = codeInternal, "la librería de plugins no entendió el pedido"
	case "no_connection":
		c, msg = codeNetwork, fmt.Sprintf("no se pudo conectar para bajar %s", what)
	case "not_found":
		c, msg = codeNoPlugin, fmt.Sprintf("%s no existe (HTTP 404)", what)
	case "rate_limited":
		c, msg = codeRateLimited, fmt.Sprintf("limitaron los pedidos para %s; esperá un rato (para GitHub, o definí GITHUB_TOKEN)", what)
	case "http_error":
		c, msg = codeNetwork, fmt.Sprintf("el servidor contestó HTTP %d para %s", int(num(d["status"])), what)
	case "bad_response":
		c, msg = codeNetwork, fmt.Sprintf("el servidor contestó algo inesperado para %s", what)
	case "bad_zip", "empty_zip":
		c, msg = codeNetwork, fmt.Sprintf("lo que se bajó de %s %s no es un zip válido", name, version)
	case "write_failed":
		c, msg = codeInternal, fmt.Sprintf("no se pudo escribir %s", str(d["path"]))
	case "lock_write_failed":
		c, msg = codeInternal, "no se pudo escribir plugins.lock"
	case "checksum_mismatch":
		c, msg = codeChecksum, fmt.Sprintf("el zip de %s %s no es el que anotó plugins.lock (otro sha256); con --force se instala igual", name, version)
	case "conflicts":
		c = codePluginConflicts
		var b strings.Builder
		fmt.Fprintf(&b, "instalar %s %s pisaría archivos (con --force se pisan):", name, version)
		for _, it := range anySlice(d["conflicts"]) {
			cf, _ := it.(map[string]any)
			why := "ya existe y no lo instaló godot-manager"
			switch cf["reason"] {
			case "modified":
				why = "se cambió a mano"
			case "owned":
				why = "es de " + str(cf["owner"])
			}
			fmt.Fprintf(&b, "\n  %s (%s)", str(cf["path"]), why)
		}
		msg = b.String()
	case "no_release":
		c = codeNoRelease
		msg = fmt.Sprintf("%s no tiene una versión que ande con Godot %s", name, str(d["godot"]))
		if n := str(d["newest"]); n != "" {
			msg += fmt.Sprintf(" (la más nueva, %s, pide %s)", n, godotRange(str(d["godot_min"]), str(d["godot_max"])))
		}
	case "no_such_version":
		c = codeNoRelease
		var vs []string
		for _, v := range anySlice(d["available"]) {
			vs = append(vs, str(v))
		}
		msg = fmt.Sprintf("%s no tiene la versión %s (hay: %s)", name, version, strings.Join(vs, ", "))
	case "incompatible":
		c, msg = codeIncompatible, fmt.Sprintf("%s %s pide %s y el proyecto usa Godot %s (con --force se instala igual)", name, version, godotRange(str(d["godot_min"]), str(d["godot_max"])), str(d["godot"]))
	case "not_in_manifest":
		c, msg = codeNoPlugin, fmt.Sprintf("'%s' no está en plugins.json", name)
	case "not_installed":
		c, msg = codeNoPlugin, fmt.Sprintf("'%s' no está instalado (godot-manager plugins install)", name)
	case "name_taken":
		c, msg = codeInvalidArgs, fmt.Sprintf("ya hay un plugin '%s' en plugins.json (de %s): elegí otro nombre con --name", name, source)
	case "bad_manifest":
		c, msg = codeInvalidArgs, "plugins.json no es JSON válido"
	case "bad_preset":
		c, msg = codeNoPreset, fmt.Sprintf("%s no existe o no es JSON válido", str(d["path"]))
	default:
		c, msg = codeInternal, "la librería de plugins falló: "+code
	}
	details := map[string]any{"reason": code}
	for k, v := range d {
		details[k] = v
	}
	return &cliError{Code: c, Msg: msg, Details: details}
}

// "Godot 4.6+", "Godot 4.3 a 4.5"...
func godotRange(low, high string) string {
	switch {
	case low != "" && high != "":
		return fmt.Sprintf("Godot %s a %s", low, high)
	case low != "":
		return fmt.Sprintf("Godot %s+", low)
	case high != "":
		return fmt.Sprintf("Godot %s o anterior", high)
	}
	return "otra versión de Godot"
}

func str(v any) string {
	if s, ok := v.(string); ok {
		return s
	}
	if v == nil {
		return ""
	}
	return fmt.Sprint(v)
}

func num(v any) float64 {
	f, _ := v.(float64)
	return f
}

func anySlice(v any) []any {
	s, _ := v.([]any)
	return s
}

func anyMap(v any) map[string]any {
	m, _ := v.(map[string]any)
	return m
}
