package manager

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

const buildsRepo = "godotengine/godot-builds"

var (
	githubAPI = "https://api.github.com/repos/" + buildsRepo
	githubDL  = "https://github.com/" + buildsRepo + "/releases/download"

	// Sin timeout total (las descargas son largas), pero si para la respuesta.
	httpClient = &http.Client{Transport: func() http.RoundTripper {
		t := http.DefaultTransport.(*http.Transport).Clone()
		t.ResponseHeaderTimeout = 60 * time.Second
		return t
	}()}

	errNotFound = errors.New("no encontrado")
)

func newRequest(method, url string) (*http.Request, error) {
	req, err := http.NewRequest(method, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "godot-manager/"+Version)
	if strings.HasPrefix(url, "https://api.github.com/") {
		req.Header.Set("Accept", "application/vnd.github+json")
		// opcional: sube el limite de 60 pedidos/hora de la API anonima
		if t := os.Getenv("GITHUB_TOKEN"); t != "" {
			req.Header.Set("Authorization", "Bearer "+t)
		}
	}
	return req, nil
}

func httpGet(url string) (*http.Response, error) {
	req, err := newRequest("GET", url)
	if err != nil {
		return nil, err
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("no se pudo descargar %s: %w", url, err)
	}
	if resp.StatusCode == http.StatusOK {
		return resp, nil
	}
	resp.Body.Close()
	switch {
	case resp.StatusCode == http.StatusNotFound:
		return nil, errNotFound
	case (resp.StatusCode == http.StatusForbidden || resp.StatusCode == http.StatusTooManyRequests) &&
		strings.HasPrefix(url, "https://api.github.com/"):
		return nil, errors.New("la API de GitHub limito los pedidos; espera un rato o defini GITHUB_TOKEN")
	}
	return nil, fmt.Errorf("no se pudo descargar %s (HTTP %d)", url, resp.StatusCode)
}

func getJSON(url string, v any) error {
	resp, err := httpGet(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if err := json.NewDecoder(resp.Body).Decode(v); err != nil {
		return fmt.Errorf("respuesta invalida de %s: %w", url, err)
	}
	return nil
}

type asset struct {
	Name   string `json:"name"`
	Size   int64  `json:"size"`
	Digest string `json:"digest"` // "sha256:<hex>"
}

// sha256 que expone la API de GitHub para el asset, o "" si no hay.
func (a *asset) sha256() string {
	if h, ok := strings.CutPrefix(a.Digest, "sha256:"); ok {
		return h
	}
	return ""
}

type release struct {
	TagName     string  `json:"tag_name"`
	Prerelease  bool    `json:"prerelease"`
	PublishedAt string  `json:"published_at"`
	Assets      []asset `json:"assets"`
}

func (r *release) asset(name string) *asset {
	for i := range r.Assets {
		if r.Assets[i].Name == name {
			return &r.Assets[i]
		}
	}
	return nil
}

func getRelease(tag string) (*release, error) {
	var r release
	err := getJSON(githubAPI+"/releases/tags/"+tag, &r)
	if errors.Is(err, errNotFound) {
		return nil, fmt.Errorf("no existe la release '%s'. Revisa el tag exacto con 'godot-manager list-remote'", tag)
	}
	if err != nil {
		return nil, err
	}
	return &r, nil
}

// godot-builds mezcla stables y pre-releases (dev/beta/rc) en el mismo repo,
// se distinguen por el flag "prerelease". La API las devuelve ordenadas por
// fecha de creacion, la mas nueva primero.
func listReleases() ([]release, error) {
	var rs []release
	err := getJSON(githubAPI+"/releases?per_page=60", &rs)
	return rs, err
}

// sha512 del manifest oficial releases/godot-<tag>.json de godot-builds, o "".
func manifestChecksum(tag, file string) string {
	var m struct {
		Files []struct {
			Filename string `json:"filename"`
			Checksum string `json:"checksum"`
		} `json:"files"`
	}
	url := "https://raw.githubusercontent.com/" + buildsRepo + "/main/releases/godot-" + tag + ".json"
	if getJSON(url, &m) != nil {
		return ""
	}
	for _, f := range m.Files {
		if f.Filename == file {
			return f.Checksum
		}
	}
	return ""
}

// Cuerpo de un pedido HTTP Range [start, end].
func rangeGet(url string, start, end int64) (io.ReadCloser, error) {
	req, err := newRequest("GET", url)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Range", fmt.Sprintf("bytes=%d-%d", start, end))
	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("no se pudo descargar %s: %w", url, err)
	}
	if resp.StatusCode != http.StatusPartialContent {
		resp.Body.Close()
		return nil, fmt.Errorf("el servidor no soporta descargas parciales (HTTP %d)", resp.StatusCode)
	}
	return resp.Body, nil
}
