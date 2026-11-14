package manager

import (
	"errors"
	"fmt"
)

// Codigos de error estables: con --json la UI los distingue por aca, y
// muestra el mensaje tal cual.
const (
	codeNotInstalled      = "not_installed"
	codeNoDefault         = "no_default"
	codeNoRelease         = "no_release"
	codeNoBuild           = "no_build_for_platform"
	codeNotAvailable      = "not_available" // la release no trae simbolos/templates para eso
	codeRateLimited       = "rate_limited"
	codeNetwork           = "network"
	codeChecksum          = "checksum"
	codeInvalidArgs       = "invalid_args"
	codeUnknownCommand    = "unknown_command"
	codeNeedsConfirmation = "needs_confirmation"
	codeBadToken          = "bad_token"          // GITHUB_TOKEN rechazado por la API
	codeAlreadyInstalled  = "already_installed"  // add sobre un nombre existente sin --force
	codeLaunchFailed      = "launch_failed"      // el binario no se pudo ejecutar
	codeNotAProject       = "not_a_project"      // no hay project.godot en la carpeta ni mas arriba
	codeNoPlugin          = "no_plugin"          // el plugin pedido no esta en el proyecto
	codeCannotSelfUpdate  = "cannot_self_update" // self-update en una instalacion que no puede tocar
	codeInternal          = "internal"
)

type cliError struct {
	Code    string
	Msg     string
	Details map[string]any // campos extra en el JSON del error
}

func (e *cliError) Error() string { return e.Msg }

func errf(code, format string, a ...any) error {
	return &cliError{Code: code, Msg: fmt.Sprintf(format, a...)}
}

// Codigo y campos extra de un error; los que no son cliError son "internal".
func errorInfo(err error) (string, map[string]any) {
	var ce *cliError
	if errors.As(err, &ce) {
		return ce.Code, ce.Details
	}
	return codeInternal, nil
}
