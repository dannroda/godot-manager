package manager

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
)

// Archivo opcional en la carpeta de una version con la ruta (relativa a la
// carpeta, o absoluta) de su binario. Se usa donde no conviene un symlink
// "godot": Windows (sin symlinks y con el _console.exe al lado), incluido
// 'add --symlink'.
const binMarker = ".godot-bin"

func validName(name string) bool {
	return name != "" && name != "." && name != ".." && !strings.ContainsAny(name, `/\`) &&
		!strings.HasPrefix(name, ".")
}

func isExecutable(p string) bool {
	fi, err := os.Stat(p)
	if err != nil || !fi.Mode().IsRegular() {
		return false
	}
	return runtime.GOOS == "windows" || fi.Mode()&0o111 != 0
}

// Binario de una version instalada.
func versionBinary(name string) (string, bool) {
	if !validName(name) {
		return "", false
	}
	dir := filepath.Join(versionsDir, name)
	if data, err := os.ReadFile(filepath.Join(dir, binMarker)); err == nil {
		p := strings.TrimSpace(string(data))
		if !filepath.IsAbs(p) {
			p = filepath.Join(dir, p)
		}
		return p, isExecutable(p)
	}
	for _, n := range []string{"godot", "godot.exe"} {
		if p := filepath.Join(dir, n); isExecutable(p) {
			return p, true
		}
	}
	return "", false
}

// Binario de una version instalada, o error si no existe.
func requireInstalled(name string) (string, error) {
	if name == "" {
		return "", errf(codeInvalidArgs, "falta el nombre de la version")
	}
	bin, ok := versionBinary(name)
	if !ok {
		return "", errf(codeNotInstalled, "'%s' no esta instalada (ver 'godot-manager list')", name)
	}
	return bin, nil
}

func installedVersions() []string {
	ents, _ := os.ReadDir(versionsDir)
	var out []string
	for _, e := range ents {
		if e.IsDir() && validName(e.Name()) {
			out = append(out, e.Name())
		}
	}
	sort.Strings(out)
	return out
}

func sameFile(a, b string) bool {
	ra, err1 := filepath.EvalSymlinks(a)
	rb, err2 := filepath.EvalSymlinks(b)
	return err1 == nil && err2 == nil && ra == rb
}

// Nombre de la version default, o "".
func defaultVersion() string {
	if data, err := os.ReadFile(filepath.Join(godotDir, "default")); err == nil {
		if v := strings.TrimSpace(string(data)); v != "" {
			return v
		}
	}
	// instalaciones anteriores solo tienen el symlink "current"
	current := filepath.Join(godotDir, "current")
	if _, err := os.Lstat(current); err != nil {
		return ""
	}
	for _, v := range installedVersions() {
		if bin, ok := versionBinary(v); ok && sameFile(bin, current) {
			return v
		}
	}
	return ""
}

func setDefault(name, bin string) error {
	if err := os.MkdirAll(godotDir, 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(godotDir, "default"), []byte(name+"\n"), 0o644); err != nil {
		return err
	}
	if runtime.GOOS == "windows" {
		return nil
	}
	// $GODOT_DIR/current sigue existiendo para quien lo use directo
	link := filepath.Join(godotDir, "current")
	os.Remove(link)
	return os.Symlink(bin, link)
}

func clearDefault() {
	os.Remove(filepath.Join(godotDir, "default"))
	os.Remove(filepath.Join(godotDir, "current"))
}

type resolution struct {
	Path    string `json:"path"`
	Version string `json:"version"`
	Source  string `json:"source"` // ruta del .godot-version, o "default"
}

// Busca un .godot-version subiendo desde el directorio actual; si no hay,
// usa la default global.
func resolve() (*resolution, error) {
	dir, err := os.Getwd()
	if err != nil {
		return nil, err
	}
	for {
		f := filepath.Join(dir, ".godot-version")
		if data, err := os.ReadFile(f); err == nil {
			ver := strings.TrimSpace(string(data))
			bin, ok := versionBinary(ver)
			if !ok {
				return nil, &cliError{
					Code:    codeNotInstalled,
					Msg:     fmt.Sprintf("version '%s' (de %s) no esta instalada", ver, f),
					Details: map[string]any{"version": ver, "source": f},
				}
			}
			return &resolution{bin, ver, f}, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	ver := defaultVersion()
	if ver == "" {
		return nil, errf(codeNoDefault, "no hay version default (usa 'godot-manager set <ver>')")
	}
	bin, ok := versionBinary(ver)
	if !ok {
		return nil, &cliError{
			Code:    codeNotInstalled,
			Msg:     fmt.Sprintf("la version default '%s' no esta instalada", ver),
			Details: map[string]any{"version": ver, "source": "default"},
		}
	}
	return &resolution{bin, ver, "default"}, nil
}
