package manager

import (
	"bufio"
	"encoding/json"
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

var stdin = bufio.NewReader(os.Stdin)

func confirm(question string) bool {
	fmt.Printf("%s [s/N] ", question)
	answer, _ := stdin.ReadString('\n')
	switch strings.TrimSpace(answer) {
	case "s", "S", "y", "Y":
		return true
	}
	return false
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
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	return enc.Encode(v)
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
