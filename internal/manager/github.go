package manager

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
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

// Si url es de la API de GitHub (la real, o la de githubAPI en los tests).
func isAPI(u string) bool {
	return strings.HasPrefix(u, "https://api.github.com/") || strings.HasPrefix(u, apiOrigin())
}

func apiOrigin() string {
	p, err := url.Parse(githubAPI)
	if err != nil {
		return githubAPI
	}
	return p.Scheme + "://" + p.Host + "/"
}

func newRequest(method, u string) (*http.Request, error) {
	req, err := http.NewRequest(method, u, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "godot-manager/"+Version)
	if isAPI(u) {
		req.Header.Set("Accept", "application/vnd.github+json")
		// opcional: sube el limite de 60 pedidos/hora de la API anonima
		if t := os.Getenv("GITHUB_TOKEN"); t != "" {
			req.Header.Set("Authorization", "Bearer "+t)
		}
	}
	return req, nil
}

func httpGet(u string) (*http.Response, error) {
	req, err := newRequest("GET", u)
	if err != nil {
		return nil, err
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, errf(codeNetwork, "no se pudo descargar %s: %v", u, err)
	}
	if resp.StatusCode == http.StatusOK {
		return resp, nil
	}
	resp.Body.Close()
	switch {
	case resp.StatusCode == http.StatusNotFound:
		return nil, errNotFound
	case !isAPI(u):
	case resp.StatusCode == http.StatusUnauthorized:
		return nil, errf(codeBadToken, "la API de GitHub rechazo GITHUB_TOKEN (HTTP 401): revisalo o borralo")
	case resp.StatusCode == http.StatusTooManyRequests || rateLimited(resp.Header):
		return nil, errf(codeRateLimited, "la API de GitHub limito los pedidos; espera un rato o defini GITHUB_TOKEN")
	case resp.StatusCode == http.StatusForbidden && os.Getenv("GITHUB_TOKEN") != "":
		return nil, errf(codeBadToken, "la API de GitHub rechazo GITHUB_TOKEN (HTTP 403, sin permiso): revisalo o borralo")
	case resp.StatusCode == http.StatusForbidden:
		return nil, errf(codeRateLimited, "la API de GitHub limito los pedidos; espera un rato o defini GITHUB_TOKEN")
	}
	return nil, errf(codeNetwork, "no se pudo descargar %s (HTTP %d)", u, resp.StatusCode)
}

// Si un 403 de la API es por limite de pedidos (primario o secundario).
func rateLimited(h http.Header) bool {
	return h.Get("X-RateLimit-Remaining") == "0" || h.Get("Retry-After") != ""
}

// Decodifica el JSON de u en v; devuelve los headers de la respuesta.
func getJSON(u string, v any) (http.Header, error) {
	resp, err := httpGet(u)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if err := json.NewDecoder(resp.Body).Decode(v); err != nil {
		return nil, errf(codeNetwork, "respuesta invalida de %s: %v", u, err)
	}
	return resp.Header, nil
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
	HTMLURL     string  `json:"html_url"`
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
	_, err := getJSON(githubAPI+"/releases/tags/"+tag, &r)
	if errors.Is(err, errNotFound) {
		return nil, errf(codeNoRelease, "no existe la release '%s'. Revisa el tag exacto con 'godot-manager list-remote'", tag)
	}
	if err != nil {
		return nil, err
	}
	return &r, nil
}

// Todas las releases, siguiendo la paginacion (header Link). godot-builds
// mezcla stables y pre-releases (dev/beta/rc) en el mismo repo, se distinguen
// por el flag "prerelease". La API las devuelve ordenadas por fecha de
// creacion, la mas nueva primero.
func listReleases() ([]release, error) {
	var all []release
	next := githubAPI + "/releases?per_page=100"
	for next != "" {
		var page []release
		h, err := getJSON(next, &page)
		if err != nil {
			return nil, err
		}
		all = append(all, page...)
		next = nextLink(h.Get("Link"))
		if next != "" && !isAPI(next) {
			return nil, fmt.Errorf("paginacion inesperada: %s", next)
		}
	}
	return all, nil
}

// URL con rel="next" de un header Link, o "".
func nextLink(link string) string {
	for _, part := range strings.Split(link, ",") {
		u, params, ok := strings.Cut(part, ";")
		if !ok || !strings.Contains(params, `rel="next"`) {
			continue
		}
		u = strings.TrimSpace(u)
		if strings.HasPrefix(u, "<") && strings.HasSuffix(u, ">") {
			return u[1 : len(u)-1]
		}
	}
	return ""
}

// sha512 del manifest oficial releases/godot-<tag>.json de godot-builds, o "".
func manifestChecksum(tag, file string) string {
	var m struct {
		Files []struct {
			Filename string `json:"filename"`
			Checksum string `json:"checksum"`
		} `json:"files"`
	}
	u := "https://raw.githubusercontent.com/" + buildsRepo + "/main/releases/godot-" + tag + ".json"
	if _, err := getJSON(u, &m); err != nil {
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
func rangeGet(u string, start, end int64) (io.ReadCloser, error) {
	req, err := newRequest("GET", u)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Range", fmt.Sprintf("bytes=%d-%d", start, end))
	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, errf(codeNetwork, "no se pudo descargar %s: %v", u, err)
	}
	if resp.StatusCode != http.StatusPartialContent {
		resp.Body.Close()
		return nil, errf(codeNetwork, "el servidor no soporta descargas parciales (HTTP %d)", resp.StatusCode)
	}
	return resp.Body, nil
}
