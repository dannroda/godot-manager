package manager

import (
	"archive/zip"
	"compress/flate"
	"errors"
	"fmt"
	"hash/crc32"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// Ruta de salida segura para una entrada de un zip.
func zipEntryPath(dest, name string) (string, error) {
	if !filepath.IsLocal(filepath.FromSlash(name)) {
		return "", fmt.Errorf("ruta invalida en el zip: %s", name)
	}
	return filepath.Join(dest, filepath.FromSlash(name)), nil
}

func entryPerm(f *zip.File, def os.FileMode) os.FileMode {
	if p := f.Mode().Perm(); p != 0 {
		return p | 0o600
	}
	return def
}

// Extrae un zip local en dest. keep filtra por nombre (nil = todo).
func extractZip(src, dest string, keep func(name string) bool) error {
	zr, err := zip.OpenReader(src)
	if err != nil {
		return fmt.Errorf("zip invalido %s: %w", filepath.Base(src), err)
	}
	defer zr.Close()
	for _, f := range zr.File {
		if keep != nil && !keep(f.Name) {
			continue
		}
		out, err := zipEntryPath(dest, f.Name)
		if err != nil {
			return err
		}
		if err := extractEntry(f, out); err != nil {
			return err
		}
	}
	return nil
}

func extractEntry(f *zip.File, out string) error {
	mode := f.Mode()
	if mode.IsDir() {
		return os.MkdirAll(out, 0o755)
	}
	if err := os.MkdirAll(filepath.Dir(out), 0o755); err != nil {
		return err
	}
	rc, err := f.Open()
	if err != nil {
		return err
	}
	defer rc.Close()
	if mode&os.ModeSymlink != 0 && runtime.GOOS != "windows" {
		target, err := io.ReadAll(rc)
		if err != nil {
			return err
		}
		os.Remove(out)
		return os.Symlink(string(target), out)
	}
	os.Remove(out) // por si es un symlink: no escribir a traves de el
	w, err := os.OpenFile(out, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, entryPerm(f, 0o644))
	if err != nil {
		return err
	}
	if _, err := io.Copy(w, rc); err != nil {
		w.Close()
		return fmt.Errorf("%s: %w", f.Name, err)
	}
	return w.Close()
}

// io.ReaderAt sobre una URL con pedidos HTTP Range, con una ventana cacheada
// para que leer el indice del zip no haga un pedido por cada lectura chica.
type httpReaderAt struct {
	url      string
	size     int64
	cache    []byte
	cacheOff int64
}

func (h *httpReaderAt) ReadAt(p []byte, off int64) (int, error) {
	if off >= h.size {
		return 0, io.EOF
	}
	end := off + int64(len(p))
	if off >= h.cacheOff && end <= h.cacheOff+int64(len(h.cache)) {
		return copy(p, h.cache[off-h.cacheOff:]), nil
	}
	// lecturas chicas (encabezados locales) van exactas; las grandes (el
	// indice, de a bloques) traen una ventana de 64 KB
	fetchEnd := end
	if len(p) > 64 {
		fetchEnd = max(end, off+64<<10)
	}
	fetchEnd = min(fetchEnd, h.size)
	body, err := rangeGet(h.url, off, fetchEnd-1)
	if err != nil {
		return 0, err
	}
	data, err := io.ReadAll(body)
	body.Close()
	if err != nil {
		return 0, err
	}
	if len(p) > 64 {
		h.cache, h.cacheOff = data, off
	}
	n := copy(p, data)
	if n < len(p) {
		return n, io.EOF
	}
	return n, nil
}

// Extrae de un zip remoto solo las entradas que empiezan con alguno de los
// prefijos, sin bajarlo entero (como el Export Template Manager del editor):
// lee el indice (central directory) del final del archivo y despues pide con
// HTTP Range el tramo de cada entrada. Cada archivo se verifica con su CRC32.
func remoteUnzip(url, dest string, prefixes []string) error {
	req, err := newRequest("HEAD", url)
	if err != nil {
		return err
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("no se pudo descargar %s: %w", url, err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK || resp.ContentLength <= 0 {
		return fmt.Errorf("no se pudo descargar %s (HTTP %d)", url, resp.StatusCode)
	}
	size := resp.ContentLength

	// el storage de GitHub no acepta rangos por sufijo (bytes=-N): se pide la
	// cola con el tamaño ya conocido
	ra := &httpReaderAt{url: url, size: size}
	tailStart := max(0, size-64<<10)
	if _, err := ra.ReadAt(make([]byte, size-tailStart), tailStart); err != nil && !errors.Is(err, io.EOF) {
		return err
	}
	zr, err := zip.NewReader(ra, size)
	if err != nil {
		return fmt.Errorf("no se pudo leer el indice del zip: %w", err)
	}

	var entries []*zip.File
	var total int64
	for _, f := range zr.File {
		if strings.HasSuffix(f.Name, "/") || !hasAnyPrefix(f.Name, prefixes) {
			continue
		}
		if f.Flags&1 != 0 || (f.Method != zip.Store && f.Method != zip.Deflate) {
			return fmt.Errorf("%s usa un formato no soportado", f.Name)
		}
		if _, err := zipEntryPath(dest, f.Name); err != nil {
			return err
		}
		entries = append(entries, f)
		total += int64(f.CompressedSize64)
	}
	fmt.Printf("%d archivos, %.0f MB a descargar\n", len(entries), float64(total)/(1<<20))

	p := newProgress(total)
	for _, f := range entries {
		p.label = filepath.Base(f.Name)
		if err := remoteEntry(ra, f, dest, p); err != nil {
			p.finish()
			return err
		}
	}
	if len(entries) > 0 {
		p.finish()
	}
	return nil
}

func hasAnyPrefix(s string, prefixes []string) bool {
	for _, p := range prefixes {
		if strings.HasPrefix(s, p) {
			return true
		}
	}
	return false
}

func remoteEntry(ra *httpReaderAt, f *zip.File, dest string, p *progress) error {
	out, _ := zipEntryPath(dest, f.Name)
	if err := os.MkdirAll(filepath.Dir(out), 0o755); err != nil {
		return err
	}
	w, err := os.OpenFile(out, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, entryPerm(f, 0o644))
	if err != nil {
		return err
	}
	defer w.Close()

	crc := crc32.NewIEEE()
	var written int64
	if f.CompressedSize64 > 0 {
		off, err := f.DataOffset()
		if err != nil {
			return err
		}
		body, err := rangeGet(ra.url, off, off+int64(f.CompressedSize64)-1)
		if err != nil {
			return err
		}
		defer body.Close()
		var r io.Reader = io.TeeReader(body, p)
		if f.Method == zip.Deflate {
			fr := flate.NewReader(r)
			defer fr.Close()
			r = fr
		}
		written, err = io.Copy(io.MultiWriter(w, crc), r)
		if err != nil {
			return fmt.Errorf("%s: %w", f.Name, err)
		}
	}
	if crc.Sum32() != f.CRC32 || uint64(written) != f.UncompressedSize64 {
		return fmt.Errorf("%s llego corrupto (CRC32 no coincide)", f.Name)
	}
	return w.Close()
}
