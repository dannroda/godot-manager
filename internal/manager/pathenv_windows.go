//go:build windows

package manager

import (
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
	"unsafe"
)

// El PATH del usuario esta en HKCU\Environment (REG_EXPAND_SZ). Despues de
// cambiarlo se avisa con WM_SETTINGCHANGE, asi las terminales que se abran
// desde el Explorador ya lo ven.

var (
	advapi32           = syscall.NewLazyDLL("advapi32.dll")
	user32             = syscall.NewLazyDLL("user32.dll")
	procRegSetValueEx  = advapi32.NewProc("RegSetValueExW")
	procSendMessageTmo = user32.NewProc("SendMessageTimeoutW")
)

// La clave del PATH del usuario (los tests usan otra).
var envKey = `Environment`

const (
	machineEnvKey   = `SYSTEM\CurrentControlSet\Control\Session Manager\Environment`
	hwndBroadcast   = 0xffff
	wmSettingChange = 0x001a
	smtoAbortIfHung = 0x0002
)

func pathTarget() string {
	return "PATH del usuario"
}

// Valor y tipo de un REG_SZ / REG_EXPAND_SZ; "" si no existe.
func regGetString(root syscall.Handle, key, name string) (string, uint32, error) {
	var h syscall.Handle
	if err := syscall.RegOpenKeyEx(root, syscall.StringToUTF16Ptr(key), 0, syscall.KEY_READ, &h); err != nil {
		return "", 0, err
	}
	defer syscall.RegCloseKey(h)
	var typ, n uint32
	err := syscall.RegQueryValueEx(h, syscall.StringToUTF16Ptr(name), nil, &typ, nil, &n)
	if errors.Is(err, syscall.ERROR_FILE_NOT_FOUND) {
		return "", syscall.REG_EXPAND_SZ, nil
	}
	if err != nil {
		return "", 0, err
	}
	buf := make([]uint16, n/2+1)
	if err := syscall.RegQueryValueEx(h, syscall.StringToUTF16Ptr(name), nil, &typ, (*byte)(unsafe.Pointer(&buf[0])), &n); err != nil {
		return "", 0, err
	}
	return syscall.UTF16ToString(buf), typ, nil
}

func regSetString(key, name, value string, typ uint32) error {
	var h syscall.Handle
	if err := syscall.RegOpenKeyEx(syscall.HKEY_CURRENT_USER, syscall.StringToUTF16Ptr(key), 0, syscall.KEY_SET_VALUE, &h); err != nil {
		return err
	}
	defer syscall.RegCloseKey(h)
	data, err := syscall.UTF16FromString(value)
	if err != nil {
		return err
	}
	r, _, _ := procRegSetValueEx.Call(uintptr(h), uintptr(unsafe.Pointer(syscall.StringToUTF16Ptr(name))), 0,
		uintptr(typ), uintptr(unsafe.Pointer(&data[0])), uintptr(len(data)*2))
	if r != 0 {
		return syscall.Errno(r)
	}
	env := syscall.StringToUTF16Ptr("Environment")
	procSendMessageTmo.Call(hwndBroadcast, wmSettingChange, 0, uintptr(unsafe.Pointer(env)), smtoAbortIfHung, 2000, 0)
	return nil
}

func samePathEntry(entry, dir string) bool {
	e := strings.TrimRight(expandEnv(strings.TrimSpace(entry)), `\/`)
	return e != "" && strings.EqualFold(filepath.Clean(e), filepath.Clean(dir))
}

// %VAR% -> valor, como hace Windows con un REG_EXPAND_SZ.
var envRef = regexp.MustCompile(`%([^%]+)%`)

func expandEnv(s string) string {
	return envRef.ReplaceAllStringFunc(s, func(m string) string {
		if v, ok := os.LookupEnv(m[1 : len(m)-1]); ok {
			return v
		}
		return m
	})
}

func pathHas(list, dir string) bool {
	for _, e := range strings.Split(list, ";") {
		if samePathEntry(e, dir) {
			return true
		}
	}
	return false
}

// Si una terminal nueva lo encuentra: la carpeta esta en el PATH del usuario
// o en el del sistema (el de este proceso puede ser viejo).
func onPath(exe string) bool {
	dir := filepath.Dir(exe)
	user, _, _ := regGetString(syscall.HKEY_CURRENT_USER, envKey, "Path")
	machine, _, _ := regGetString(syscall.HKEY_LOCAL_MACHINE, machineEnvKey, "Path")
	return pathHas(user, dir) || pathHas(machine, dir)
}

func addToPath(exe string) error {
	dir := filepath.Dir(exe)
	cur, typ, err := regGetString(syscall.HKEY_CURRENT_USER, envKey, "Path")
	if err != nil {
		return err
	}
	if pathHas(cur, dir) {
		return nil
	}
	if cur = strings.TrimRight(cur, ";"); cur != "" {
		cur += ";"
	}
	return regSetString(envKey, "Path", cur+dir, typ)
}

func removeFromPath(exe string) error {
	dir := filepath.Dir(exe)
	cur, typ, err := regGetString(syscall.HKEY_CURRENT_USER, envKey, "Path")
	if err != nil {
		return err
	}
	var keep []string
	for _, e := range strings.Split(cur, ";") {
		if e != "" && !samePathEntry(e, dir) {
			keep = append(keep, e)
		}
	}
	next := strings.Join(keep, ";")
	if next == strings.TrimRight(cur, ";") {
		return nil
	}
	return regSetString(envKey, "Path", next, typ)
}
