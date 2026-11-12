package manager

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

func warn(format string, a ...any) {
	fmt.Fprintf(os.Stderr, "Aviso: "+format+"\n", a...)
}

var (
	stdin = bufio.NewReader(os.Stdin)
	// --yes: confirmar sin preguntar
	assumeYes bool
)

// Pregunta por la terminal. Con --yes es si; sin terminal (o con --json) y
// sin --yes es un error, en vez de quedarse esperando o asumir que no.
func confirm(question string) (bool, error) {
	if assumeYes {
		return true, nil
	}
	if out.isJSON() || !isTerminal(os.Stdin) {
		return false, errf(codeNeedsConfirmation, "hace falta confirmar \"%s\" y no hay terminal: usa --yes", question)
	}
	fmt.Printf("%s [s/N] ", question)
	answer, _ := stdin.ReadString('\n')
	switch strings.TrimSpace(answer) {
	case "s", "S", "y", "Y":
		return true, nil
	}
	return false, nil
}

// Saca --yes / -y de args.
func yesFlag(args []string) []string {
	out := args[:0:0]
	for _, a := range args {
		if a == "--yes" || a == "-y" {
			assumeYes = true
		} else {
			out = append(out, a)
		}
	}
	return out
}

// Tamaño en formato corto, como numfmt --to=iec / du -h.
func humanSize(n int64) string {
	if n < 1024 {
		return fmt.Sprintf("%d", n)
	}
	v := float64(n)
	units := "KMGTPE"
	i := -1
	for v >= 1024 && i < len(units)-1 {
		v /= 1024
		i++
	}
	if v < 10 {
		return fmt.Sprintf("%.1f%c", v, units[i])
	}
	return fmt.Sprintf("%.0f%c", v, units[i])
}

func dirSize(dir string) int64 {
	var total int64
	filepath.WalkDir(dir, func(_ string, d fs.DirEntry, err error) error {
		if err == nil && d.Type().IsRegular() {
			if fi, err := d.Info(); err == nil {
				total += fi.Size()
			}
		}
		return nil
	})
	return total
}

// Copia src a dst (reemplazandolo, sin escribir a traves de un symlink).
func copyFile(src, dst string, perm os.FileMode) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	tmp := dst + ".tmp"
	out, err := os.OpenFile(tmp, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, perm)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		os.Remove(tmp)
		return err
	}
	if err := out.Close(); err != nil {
		os.Remove(tmp)
		return err
	}
	os.Remove(dst)
	return os.Rename(tmp, dst)
}

// Mueve el contenido de src dentro de dst, reemplazando lo que ya exista.
func moveContents(src, dst string) error {
	if err := os.MkdirAll(dst, 0o755); err != nil {
		return err
	}
	ents, err := os.ReadDir(src)
	if err != nil {
		return err
	}
	for _, e := range ents {
		target := filepath.Join(dst, e.Name())
		if err := os.RemoveAll(target); err != nil {
			return err
		}
		if err := os.Rename(filepath.Join(src, e.Name()), target); err != nil {
			return err
		}
	}
	return nil
}

func printJSON(v any) error {
	enc := json.NewEncoder(out.stdout)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "  ")
	return enc.Encode(v)
}

// Si args empieza con --dir <c>, --dir=<c> o -C <c>, devuelve el resto y la
// carpeta.
func takeDirFlag(args []string) (rest []string, dir string, ok bool, err error) {
	if len(args) == 0 {
		return args, "", false, nil
	}
	if d, found := strings.CutPrefix(args[0], "--dir="); found {
		if d == "" {
			return nil, "", false, errors.New("--dir necesita una carpeta")
		}
		return args[1:], d, true, nil
	}
	if args[0] == "--dir" || args[0] == "-C" {
		if len(args) < 2 || args[1] == "" {
			return nil, "", false, fmt.Errorf("%s necesita una carpeta", args[0])
		}
		return args[2:], args[1], true, nil
	}
	return args, "", false, nil
}

// Saca --dir (en cualquier posicion) de args; la ultima gana sobre dir.
func stripDirFlag(args []string, dir string) ([]string, string, error) {
	out := args[:0:0]
	for len(args) > 0 {
		rest, d, ok, err := takeDirFlag(args)
		if err != nil {
			return nil, "", err
		}
		if ok {
			args, dir = rest, d
			continue
		}
		out = append(out, args[0])
		args = args[1:]
	}
	return out, dir, nil
}

// Saca "--json" de args.
func jsonFlag(args []string, already bool) ([]string, bool) {
	out := args[:0:0]
	found := already
	for _, a := range args {
		if a == "--json" {
			found = true
		} else {
			out = append(out, a)
		}
	}
	return out, found
}
