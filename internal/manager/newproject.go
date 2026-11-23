package manager

import (
	_ "embed"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// new <carpeta> [--name n] [--version v] [--renderer r] [--preset p]: un proyecto de Godot 4
// vacío, como lo crea el Project Manager (project.godot, icon.svg, .editorconfig, .gitignore,
// .gitattributes), con su .godot-version si se pide una versión y con los plugins de un preset.

// El ícono que el Project Manager pone en cada proyecto nuevo (el de Godot 4.8, igual al de
// las versiones anteriores de Godot 4).
//
//go:embed assets/godot_icon.svg
var godotIcon string

var renderers = map[string]struct{ feature, method string }{
	"forward_plus":     {"Forward Plus", ""},
	"mobile":           {"Mobile", "mobile"},
	"gl_compatibility": {"GL Compatibility", "gl_compatibility"},
}

func cmdNew(args []string) (map[string]any, error) {
	var rest []string
	opts := map[string]string{"--name": "", "--version": "", "--renderer": "forward_plus", "--preset": ""}
	noEnable := false
	for i := 0; i < len(args); i++ {
		a := args[i]
		key, val, hasVal := strings.Cut(a, "=")
		if _, ok := opts[key]; ok {
			if !hasVal {
				if i+1 >= len(args) {
					return nil, errf(codeInvalidArgs, "falta el valor de %s", key)
				}
				i++
				val = args[i]
			}
			opts[key] = val
			continue
		}
		if a == "--no-enable" {
			noEnable = true
			continue
		}
		if strings.HasPrefix(a, "-") {
			return nil, errf(codeInvalidArgs, "opción desconocida '%s'", a)
		}
		rest = append(rest, a)
	}
	if len(rest) != 1 {
		return nil, errf(codeInvalidArgs, "uso: godot-manager new <carpeta> [--name n] [--version v] [--renderer forward_plus|mobile|gl_compatibility] [--preset p]")
	}
	dir, err := filepath.Abs(rest[0])
	if err != nil {
		return nil, err
	}
	if fi, err := os.Stat(dir); err == nil {
		if !fi.IsDir() {
			return nil, errf(codeInvalidArgs, "%s no es una carpeta", dir)
		}
		if ents, _ := os.ReadDir(dir); len(ents) > 0 {
			return nil, errf(codeInvalidArgs, "%s ya existe y no está vacía", dir)
		}
	}
	r, ok := renderers[opts["--renderer"]]
	if !ok {
		return nil, errf(codeInvalidArgs, "renderer desconocido '%s' (forward_plus, mobile, gl_compatibility)", opts["--renderer"])
	}
	name := opts["--name"]
	if name == "" {
		name = filepath.Base(dir)
	}
	// La versión fija el número de config/features; sin --version, la default (sin escribir
	// .godot-version: el proyecto sigue a la default).
	version := opts["--version"]
	if version != "" {
		if _, err := requireInstalled(version); err != nil {
			return nil, err
		}
	}
	feature := ""
	if v := firstNonEmpty(version, defaultVersion()); v != "" {
		k, ok := parseTag(versionTag(v))
		if ok && k[0] < 4 {
			return nil, errf(codeInvalidArgs, "new crea proyectos de Godot 4 o más nuevo, y %s es Godot %d", v, k[0])
		}
		if ok {
			feature = fmt.Sprintf("%d.%d", k[0], k[1])
		}
	}
	presetFile := ""
	if opts["--preset"] != "" {
		if presetFile, err = findPreset(opts["--preset"]); err != nil {
			return nil, err
		}
	}

	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	files := map[string]string{
		"project.godot":  projectGodotText(name, feature, r.feature, r.method),
		"icon.svg":       godotIcon,
		".editorconfig":  "root = true\n\n[*]\ncharset = utf-8\n",
		".gitignore":     "# Godot 4+ specific ignores\n.godot/\n/android/\n",
		".gitattributes": "# Normalize EOL for all files that Git considers text files.\n* text=auto eol=lf\n",
	}
	if version != "" {
		files[".godot-version"] = version + "\n"
	}
	for f, body := range files {
		if err := os.WriteFile(filepath.Join(dir, f), []byte(body), 0o644); err != nil {
			return nil, err
		}
	}
	out.step("Proyecto '%s' creado en %s", name, dir)
	res := map[string]any{"path": dir, "name": name, "version": version, "preset": opts["--preset"]}
	if presetFile != "" {
		godot := version
		if godot == "" {
			godot = feature
		}
		applied, err := applyPreset(kitRun{proj: dir, godot: godot}, presetFile, !noEnable)
		if err != nil {
			// el proyecto quedó creado y su plugins.json tiene el preset: plugins install reintenta
			code, details := errorInfo(err)
			if details == nil {
				details = map[string]any{}
			}
			details["path"] = dir
			return nil, &cliError{Code: code, Details: details,
				Msg: fmt.Sprintf("el proyecto quedó creado en %s, pero no se pudieron instalar los plugins del preset: %v (después de arreglarlo: godot-manager -C \"%s\" plugins install)", dir, err, dir)}
		}
		res["plugins"] = applied["added"]
		res["enabled"] = applied["enabled"]
	}
	return res, nil
}

// El primero que no esté vacío.
func firstNonEmpty(a, b string) string {
	if a != "" {
		return a
	}
	return b
}

func projectGodotText(name, version, feature, method string) string {
	var b strings.Builder
	b.WriteString("; Engine configuration file.\n; It's best edited using the editor UI and not directly,\n; since the parameters that go here are not all obvious.\n;\n; Format:\n;   [section] ; section goes between []\n;   param=value ; assign values to parameters\n\nconfig_version=5\n\n[application]\n\n")
	fmt.Fprintf(&b, "config/name=%s\n", quoteCfg(name))
	features := []string{}
	if version != "" {
		features = append(features, quoteCfg(version))
	}
	features = append(features, quoteCfg(feature))
	fmt.Fprintf(&b, "config/features=PackedStringArray(%s)\n", strings.Join(features, ", "))
	b.WriteString("config/icon=\"res://icon.svg\"\n")
	if method != "" {
		fmt.Fprintf(&b, "\n[rendering]\n\nrenderer/rendering_method=%s\n", quoteCfg(method))
		if method == "gl_compatibility" {
			b.WriteString("renderer/rendering_method.mobile=\"gl_compatibility\"\n")
		}
	}
	return b.String()
}

func quoteCfg(s string) string {
	return `"` + strings.ReplaceAll(strings.ReplaceAll(s, `\`, `\\`), `"`, `\"`) + `"`
}
