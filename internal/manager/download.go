package manager

import (
	"crypto/sha256"
	"crypto/sha512"
	"encoding/hex"
	"errors"
	"hash"
	"io"
	"os"
	"path"
	"strings"
)

func newHash(algo string) hash.Hash {
	if algo == "sha512" {
		return sha512.New()
	}
	return sha256.New()
}

// Descarga url a dest y compara su hash contra expected.
// algo: sha256 | sha512. expected vacio = se omite la verificacion con aviso.
func downloadVerified(url, dest, algo, expected string) error {
	out.step("Descargando %s...", url)
	resp, err := httpGet(url)
	if errors.Is(err, errNotFound) {
		return errf(codeNoRelease, "no se pudo descargar %s (no existe). Revisa el tag exacto con 'godot-manager list-remote'", path.Base(url))
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
		return errf(codeNetwork, "descarga interrumpida: %v", err)
	}

	if expected == "" {
		out.warn("no hay checksum publicado para %s, se omite verificacion", path.Base(url))
		return nil
	}
	actual := hex.EncodeToString(h.Sum(nil))
	if !strings.EqualFold(actual, expected) {
		return errf(codeChecksum, "el checksum de %s no coincide\n  esperado: %s\n  obtenido: %s",
			path.Base(url), expected, actual)
	}
	out.step("Checksum verificado OK")
	return nil
}
