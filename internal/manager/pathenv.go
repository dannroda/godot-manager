package manager

import (
	"fmt"
	"path/filepath"
	"runtime"
)

// path [add|remove]: deja godot-manager y godot a mano desde cualquier
// terminal. En Windows agrega la carpeta del ejecutable al PATH del usuario;
// en Linux y macOS crea symlinks en ~/.local/bin.

type pathStatus struct {
	Dir    string `json:"dir"`     // carpeta de godot-manager
	OnPath bool   `json:"on_path"` // si una terminal nueva lo encuentra
	Target string `json:"target"`  // lo que toca add: el PATH del usuario, o ~/.local/bin
	// Por que no se puede tocar (lo instalo un gestor de paquetes), o ""
	Managed string `json:"managed"`
}

func currentPathStatus() (*pathStatus, error) {
	exe, err := selfExecutable()
	if err != nil {
		return nil, err
	}
	dir := filepath.Dir(exe)
	st := &pathStatus{Dir: dir, Target: pathTarget()}
	if pm := packageManager(runtime.GOOS, dir); pm != "" {
		st.Managed = pm
	}
	st.OnPath = onPath(exe)
	return st, nil
}

func cmdPath(args []string) (map[string]any, error) {
	sub := "status"
	if len(args) > 0 {
		sub = args[0]
	}
	if len(args) > 1 {
		return nil, errf(codeInvalidArgs, "sobra '%s'", args[1])
	}
	st, err := currentPathStatus()
	if err != nil {
		return nil, err
	}
	switch sub {
	case "status":
		if out.isJSON() {
			return nil, printJSON(st)
		}
		if st.OnPath {
			fmt.Printf("godot-manager (%s) esta en el PATH.\n", st.Dir)
		} else {
			fmt.Printf("godot-manager (%s) no esta en el PATH: 'godot-manager path add' lo agrega (%s).\n", st.Dir, st.Target)
		}
		return nil, nil
	case "add", "remove":
		if st.Managed != "" {
			return nil, errf(codePackageManaged, "lo instalo %s en %s: el PATH lo maneja ese instalador", st.Managed, st.Dir)
		}
		exe, _ := selfExecutable()
		if sub == "add" {
			err = addToPath(exe)
		} else {
			err = removeFromPath(exe)
		}
		if err != nil {
			return nil, err
		}
		st.OnPath = onPath(exe)
		if sub == "add" {
			out.step("Listo: una terminal nueva ya encuentra godot-manager y godot (%s).", st.Target)
			if !st.OnPath {
				out.warn("%s no esta en el PATH de esta sesion: agregalo en tu shell (por ejemplo en ~/.profile)", st.Target)
			}
		} else {
			out.step("Quitado de %s.", st.Target)
		}
		return map[string]any{"dir": st.Dir, "on_path": st.OnPath, "target": st.Target}, nil
	}
	return nil, errf(codeInvalidArgs, "uso: godot-manager path [add|remove]")
}
