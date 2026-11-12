package manager

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
)

// Layout:
//
//	$GODOT_DIR/versions/<nombre>/   una carpeta por version
//	$GODOT_DIR/default              nombre de la version default global
//	$GODOT_DIR/current              (unix) symlink al binario default, por compatibilidad
//	<proyecto>/.godot-version       version fijada para un proyecto
var (
	godotDir      string
	versionsDir   string
	templatesBase string
)

func initPaths() error {
	godotDir = os.Getenv("GODOT_DIR")
	if godotDir == "" {
		d, err := defaultGodotDir()
		if err != nil {
			return err
		}
		godotDir = d
	}
	versionsDir = filepath.Join(godotDir, "versions")
	d, err := defaultTemplatesBase()
	if err != nil {
		return err
	}
	templatesBase = d
	return nil
}

func defaultGodotDir() (string, error) {
	switch runtime.GOOS {
	case "windows":
		if d := os.Getenv("LOCALAPPDATA"); d != "" {
			return filepath.Join(d, "godot-manager"), nil
		}
		return "", errors.New("LOCALAPPDATA no esta definida (o defini GODOT_DIR)")
	default:
		return "/opt/godot", nil
	}
}

// Donde el editor busca los export templates.
func defaultTemplatesBase() (string, error) {
	switch runtime.GOOS {
	case "windows":
		// %APPDATA%
		d, err := os.UserConfigDir()
		if err != nil {
			return "", err
		}
		return filepath.Join(d, "Godot", "export_templates"), nil
	default:
		d := os.Getenv("XDG_DATA_HOME")
		if d == "" {
			home, err := os.UserHomeDir()
			if err != nil {
				return "", err
			}
			d = filepath.Join(home, ".local", "share")
		}
		return filepath.Join(d, "godot", "export_templates"), nil
	}
}

// Arquitectura con la convencion de nombres de los assets de Godot.
func godotArch() (string, error) {
	switch runtime.GOARCH {
	case "amd64":
		return "x86_64", nil
	case "arm64":
		return "arm64", nil
	case "386":
		return "x86_32", nil
	case "arm":
		return "arm32", nil
	}
	return "", fmt.Errorf("arquitectura no soportada: %s", runtime.GOARCH)
}

// win64, win32, windows_arm64
func windowsPlatform(arch string) string {
	switch arch {
	case "x86_64":
		return "win64"
	case "x86_32":
		return "win32"
	}
	return "windows_" + arch
}

func assetPrefix(ver string, mono bool) string {
	p := "Godot_v" + ver + "_"
	if mono {
		p += "mono_"
	}
	return p
}

// Nombres posibles del zip del editor para esta plataforma, en orden de
// preferencia.
func editorAssets(ver string, mono bool) ([]string, error) {
	arch, err := godotArch()
	if err != nil {
		return nil, err
	}
	p := assetPrefix(ver, mono)
	switch runtime.GOOS {
	case "linux":
		if mono {
			return []string{p + "linux_" + arch + ".zip"}, nil
		}
		return []string{p + "linux." + arch + ".zip"}, nil
	case "windows":
		w := windowsPlatform(arch)
		if mono {
			return []string{p + w + ".zip"}, nil
		}
		return []string{p + w + ".exe.zip"}, nil
	}
	return nil, fmt.Errorf("sistema operativo no soportado: %s", runtime.GOOS)
}

// Archivo de simbolos de debug del editor (el asset es este nombre + ".zip").
// Desde 4.8-beta1. El binario lo referencia por nombre (.gnu_debuglink), asi
// que alcanza con dejarlo al lado.
func editorSymbolsFile(ver string, mono bool) (string, error) {
	arch, err := godotArch()
	if err != nil {
		return "", err
	}
	p := assetPrefix(ver, mono)
	switch runtime.GOOS {
	case "linux":
		return p + "linux." + arch + ".debugsymbols", nil
	case "windows":
		return p + windowsPlatform(arch) + ".exe.debugsymbols", nil
	}
	return "", fmt.Errorf("los simbolos de debug del editor no estan soportados en %s", runtime.GOOS)
}

// Simbolos de templates que baja --debugsymbols sin lista explicita: los de
// la plataforma actual.
func defaultTemplateSymbols() []string {
	arch, err := godotArch()
	if err != nil {
		arch = "x86_64"
	}
	switch runtime.GOOS {
	case "windows":
		return []string{"windows_debug_" + arch + ".exe", "windows_release_" + arch + ".exe"}
	}
	return []string{"linux_debug." + arch, "linux_release." + arch}
}
