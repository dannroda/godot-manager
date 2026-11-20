package manager

import (
	"fmt"
	"path/filepath"
	"runtime"
	"strings"
)

// dirs: las carpetas que usa godot-manager. default_godot_dir es la que usaria
// sin GODOT_DIR, para que la interfaz la muestre y pueda volver a ella.

type dirsInfo struct {
	GodotDir        string `json:"godot_dir"`         // la que se usa ahora
	DefaultGodotDir string `json:"default_godot_dir"` // la que se usa sin GODOT_DIR
	Custom          bool   `json:"custom"`            // si viene de GODOT_DIR
	Versions        string `json:"versions"`
	Templates       string `json:"templates"`
}

func cmdDirs(args []string) (map[string]any, error) {
	if len(args) > 0 {
		return nil, errf(codeInvalidArgs, "sobra '%s'", args[0])
	}
	def, err := defaultGodotDir()
	if err != nil {
		def = ""
	}
	info := dirsInfo{
		GodotDir:        godotDir,
		DefaultGodotDir: def,
		Custom:          def == "" || !samePath(godotDir, def),
		Versions:        versionsDir,
		Templates:       templatesBase,
	}
	if out.isJSON() {
		return nil, printJSON(info)
	}
	fmt.Printf("GODOT_DIR:  %s\n", info.GodotDir)
	if info.Custom {
		fmt.Printf("por defecto: %s\n", info.DefaultGodotDir)
	}
	fmt.Printf("versiones:  %s\n", info.Versions)
	fmt.Printf("templates:  %s\n", info.Templates)
	return nil, nil
}

// Si a y b son la misma carpeta (en Windows y macOS sin mirar mayusculas).
func samePath(a, b string) bool {
	a, b = filepath.Clean(a), filepath.Clean(b)
	if runtime.GOOS == "windows" || runtime.GOOS == "darwin" {
		return strings.EqualFold(a, b)
	}
	return a == b
}
