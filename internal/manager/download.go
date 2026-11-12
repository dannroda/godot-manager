package manager

import (
	"crypto/sha256"
	"crypto/sha512"
	"encoding/hex"
	"errors"
	"fmt"
	"hash"
	"io"
	"os"
	"path"
	"strings"
	"time"
)

// Progreso de una descarga en stderr, solo si es una terminal.
type progress struct {
	total, done int64
	label       string
	last        time.Time
	tty         bool
}

func newProgress(total int64) *progress {
	return &progress{total: total, tty: isTerminal(os.Stderr)}
}

func (p *progress) Write(b []byte) (int, error) {
	p.done += int64(len(b))
	if p.tty && time.Since(p.last) > 150*time.Millisecond {
		p.print()
	}
	return len(b), nil
}

func (p *progress) print() {
	p.last = time.Now()
	const mb = 1 << 20
	if p.total > 0 {
		fmt.Fprintf(os.Stderr, "\r  %6.0f/%.0f MB %3d%%  %-40s",
			float64(p.done)/mb, float64(p.total)/mb, p.done*100/p.total, p.label)
	} else {
		fmt.Fprintf(os.Stderr, "\r  %6.0f MB  %-40s", float64(p.done)/mb, p.label)
	}
}

func (p *progress) finish() {
	if p.tty {
		p.print()
		fmt.Fprintln(os.Stderr)
	}
}

func isTerminal(f *os.File) bool {
	fi, err := f.Stat()
	return err == nil && fi.Mode()&os.ModeCharDevice != 0
}

func newHash(algo string) hash.Hash {
	if algo == "sha512" {
		return sha512.New()
	}
	return sha256.New()
}

// Descarga url a dest y compara su hash contra expected.
// algo: sha256 | sha512. expected vacio = se omite la verificacion con aviso.
func downloadVerified(url, dest, algo, expected string) error {
	fmt.Printf("Descargando %s...\n", url)
	resp, err := httpGet(url)
	if errors.Is(err, errNotFound) {
		return errors.New("no se pudo descargar (no existe). Revisa el tag exacto con 'godot-manager list-remote'")
	}
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	f, err := os.Create(dest)
	if err != nil {
		return err
	}
	h := newHash(algo)
	p := newProgress(resp.ContentLength)
	p.label = path.Base(url)
	_, err = io.Copy(io.MultiWriter(f, h, p), resp.Body)
	p.finish()
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		return fmt.Errorf("descarga interrumpida: %w", err)
	}

	if expected == "" {
		warn("no hay checksum publicado para %s, se omite verificacion", path.Base(url))
		return nil
	}
	actual := hex.EncodeToString(h.Sum(nil))
	if !strings.EqualFold(actual, expected) {
		return fmt.Errorf("el checksum de %s no coincide\n  esperado: %s\n  obtenido: %s",
			path.Base(url), expected, actual)
	}
	fmt.Println("Checksum verificado OK")
	return nil
}
