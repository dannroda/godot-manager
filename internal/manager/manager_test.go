package manager

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

// Captura lo que sale por out en el modo dado.
func capture(t *testing.T, mode outMode) (*bytes.Buffer, *bytes.Buffer) {
	t.Helper()
	var so, se bytes.Buffer
	pm, po, pe := out.mode, out.stdout, out.stderr
	out.mode, out.stdout, out.stderr = mode, &so, &se
	t.Cleanup(func() { out.mode, out.stdout, out.stderr = pm, po, pe })
	return &so, &se
}

func jsonLines(t *testing.T, s string) []map[string]any {
	t.Helper()
	var res []map[string]any
	for _, l := range strings.Split(strings.TrimSpace(s), "\n") {
		var m map[string]any
		if err := json.Unmarshal([]byte(l), &m); err != nil {
			t.Fatalf("linea no es JSON: %q", l)
		}
		res = append(res, m)
	}
	return res
}

func TestEvents(t *testing.T) {
	so, se := capture(t, modeEvents)
	out.step("Descargando %s", "x.zip")
	p := newProgress(100)
	p.label = "x.zip"
	p.Write(make([]byte, 40))
	p.Write(make([]byte, 60)) // dentro de los 250 ms: no emite
	p.finish()
	out.warn("ojo")
	out.result(map[string]any{"version": "4.3-stable"})

	ev := jsonLines(t, so.String())
	want := []string{"step", "download", "download", "warn", "done"}
	if len(ev) != len(want) {
		t.Fatalf("eventos: %v", ev)
	}
	for i, w := range want {
		if ev[i]["event"] != w {
			t.Errorf("evento %d = %v, quiero %s", i, ev[i]["event"], w)
		}
	}
	if ev[1]["done"] != 40.0 || ev[2]["done"] != 100.0 || ev[2]["total"] != 100.0 || ev[2]["file"] != "x.zip" {
		t.Errorf("download: %v %v", ev[1], ev[2])
	}
	if ev[4]["version"] != "4.3-stable" {
		t.Errorf("done: %v", ev[4])
	}
	if se.Len() != 0 {
		t.Errorf("stderr deberia estar vacio: %q", se.String())
	}
}

func TestErrorsJSON(t *testing.T) {
	so, _ := capture(t, modeJSON)
	out.step("no sale")
	out.fail(&cliError{Code: codeNotInstalled, Msg: "no esta", Details: map[string]any{"version": "4.3"}})
	ev := jsonLines(t, so.String())
	e, _ := ev[0]["error"].(map[string]any)
	if len(ev) != 1 || e["code"] != codeNotInstalled || e["message"] != "no esta" || e["version"] != "4.3" {
		t.Errorf("error: %v", ev)
	}

	so, _ = capture(t, modeEvents)
	out.fail(fmt.Errorf("algo: %w", errf(codeNetwork, "sin red")))
	ev = jsonLines(t, so.String())
	if ev[0]["event"] != "error" || ev[0]["code"] != codeNetwork {
		t.Errorf("error envuelto: %v", ev)
	}

	so, _ = capture(t, modeJSON)
	out.result(map[string]any{"version": "x"})
	ev = jsonLines(t, so.String())
	if ev[0]["ok"] != true || ev[0]["version"] != "x" {
		t.Errorf("ok: %v", ev)
	}
}

func TestCompareTags(t *testing.T) {
	ordered := []string{"custom", "3.6.3-stable", "4.7.2-stable", "4.8-dev1", "4.8-alpha2",
		"4.8-beta2", "4.8-beta10", "4.8-rc1", "4.8-stable", "4.8.1-stable"}
	for i := 1; i < len(ordered); i++ {
		if compareTags(ordered[i-1], ordered[i]) >= 0 {
			t.Errorf("%s deberia ser menor que %s", ordered[i-1], ordered[i])
		}
	}
	if compareTags("4.3-stable", "4.3.0-stable") != 0 {
		t.Error("4.3 y 4.3.0 deberian ser iguales")
	}
}

// Servidor falso de la API con 3 paginas de releases.
func fakeAPI(t *testing.T) *int {
	t.Helper()
	var hits int
	var srv *httptest.Server
	srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits++
		page := r.URL.Query().Get("page")
		var rs []release
		switch page {
		case "", "1":
			rs = []release{{TagName: "3.6.3-stable"}, {TagName: "4.8-beta3", Prerelease: true,
				Assets: []asset{{Name: "Godot_v4.8-beta3_linux.x86_64.zip", Size: 10},
					{Name: "Godot_v4.8-beta3_linux.x86_64.debugsymbols.zip"},
					{Name: "Godot_v4.8-beta3_export_templates.tpz", Size: 30}}}}
			w.Header().Set("Link", fmt.Sprintf(`<%s/repos/x/releases?per_page=100&page=2>; rel="next", <%s/repos/x/releases?page=3>; rel="last"`, srv.URL, srv.URL))
		case "2":
			rs = []release{{TagName: "4.7.2-stable"}}
			w.Header().Set("Link", fmt.Sprintf(`<%s/repos/x/releases?page=3>; rel="next"`, srv.URL))
		case "3":
			rs = []release{{TagName: "3.5-stable"}}
		}
		json.NewEncoder(w).Encode(rs)
	}))
	t.Cleanup(srv.Close)
	prev := githubAPI
	githubAPI = srv.URL + "/repos/x"
	t.Cleanup(func() { githubAPI = prev })
	return &hits
}

func TestListReleasesPaginates(t *testing.T) {
	hits := fakeAPI(t)
	rs, err := listReleases()
	if err != nil {
		t.Fatal(err)
	}
	if len(rs) != 4 || *hits != 3 {
		t.Fatalf("releases %d, pedidos %d", len(rs), *hits)
	}
	if got := newest(rs, func(r *release) bool { return !r.Prerelease }); got != "4.7.2-stable" {
		t.Errorf("ultima estable = %s", got)
	}
}

func TestListRemoteJSON(t *testing.T) {
	hits := fakeAPI(t)
	so, _ := capture(t, modeJSON)
	if err := cmdListRemote("dev"); err != nil {
		t.Fatal(err)
	}
	var vs []remoteVersion
	if err := json.Unmarshal(so.Bytes(), &vs); err != nil {
		t.Fatal(err)
	}
	if *hits != 3 {
		t.Errorf("pedidos extra: %d", *hits)
	}
	if len(vs) != 1 || vs[0].Tag != "4.8-beta3" || !vs[0].Templates || vs[0].TemplatesSize != 30 || vs[0].MonoTemplates {
		t.Fatalf("%+v", vs)
	}
	if want := runtime.GOOS == "linux" && runtime.GOARCH == "amd64"; vs[0].Editor != want || vs[0].DebugSymbols != want {
		t.Errorf("editor/simbolos para esta plataforma: %+v", vs[0])
	}
}

func TestCleanStaleTemps(t *testing.T) {
	dir := t.TempDir()
	mk := func(name, pid string, age time.Duration) string {
		p := filepath.Join(dir, name)
		os.MkdirAll(p, 0o755)
		if pid != "" {
			os.WriteFile(filepath.Join(p, tempPID), []byte(pid), 0o644)
		}
		old := time.Now().Add(-age)
		os.Chtimes(p, old, old)
		return p
	}
	dead := mk(tempPrefix+"dead", "999999999", 0)
	alive := mk(tempPrefix+"alive", fmt.Sprint(os.Getppid()), 0)
	legacyOld := mk(tempPrefix+"old", "", 48*time.Hour)
	legacyNew := mk(tempPrefix+"new", "", time.Minute)
	other := mk("4.3-stable", "999999999", 48*time.Hour)

	cleanStaleTemps(dir)
	for p, want := range map[string]bool{dead: false, alive: true, legacyOld: false, legacyNew: true, other: true} {
		if exists(p) != want {
			t.Errorf("%s: existe=%v, quiero %v", filepath.Base(p), !want, want)
		}
	}
}

func TestAPIErrorCodes(t *testing.T) {
	status, hdr := 0, map[string]string{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		for k, v := range hdr {
			w.Header().Set(k, v)
		}
		w.WriteHeader(status)
	}))
	t.Cleanup(srv.Close)
	prev := githubAPI
	githubAPI = srv.URL + "/repos/x"
	t.Cleanup(func() { githubAPI = prev })

	for _, c := range []struct {
		status int
		hdr    map[string]string
		token  string
		want   string
	}{
		{401, nil, "malo", codeBadToken},
		{403, nil, "sinpermiso", codeBadToken},
		{403, map[string]string{"X-RateLimit-Remaining": "0"}, "bueno", codeRateLimited},
		{403, map[string]string{"Retry-After": "60"}, "bueno", codeRateLimited},
		{403, nil, "", codeRateLimited},
		{429, nil, "", codeRateLimited},
		{500, nil, "", codeNetwork},
	} {
		status, hdr = c.status, c.hdr
		t.Setenv("GITHUB_TOKEN", c.token)
		_, err := httpGet(githubAPI + "/releases")
		if code, _ := errorInfo(err); code != c.want {
			t.Errorf("HTTP %d %v token=%q: %s, quiero %s", c.status, c.hdr, c.token, code, c.want)
		}
	}
}

func TestAddExisting(t *testing.T) {
	pv, pg := versionsDir, godotDir
	t.Cleanup(func() { versionsDir, godotDir = pv, pg })
	versionsDir, godotDir = filepath.Join(t.TempDir(), "versions"), t.TempDir()
	capture(t, modeJSON)
	src := filepath.Join(t.TempDir(), "bin")
	os.WriteFile(src, []byte("#!/bin/sh\n"), 0o755)
	if _, err := cmdAdd([]string{"mio", src}); err != nil {
		t.Fatal(err)
	}
	os.WriteFile(filepath.Join(versionsDir, "mio", "resto"), nil, 0o644)
	_, err := cmdAdd([]string{"mio", src})
	if code, _ := errorInfo(err); code != codeAlreadyInstalled {
		t.Fatalf("sin --force: %v", err)
	}
	if _, err := cmdAdd([]string{"--force", "mio", src}); err != nil {
		t.Fatal(err)
	}
	if exists(filepath.Join(versionsDir, "mio", "resto")) {
		t.Error("--force deberia reemplazar la carpeta entera")
	}
}

func TestLaunchError(t *testing.T) {
	capture(t, modeJSON)
	bin := filepath.Join(t.TempDir(), "no-existe")
	_, err := runBinary("x", bin, nil, true)
	code, det := errorInfo(err)
	if code != codeLaunchFailed || det["path"] != bin || strings.Contains(err.Error(), "fork/exec") {
		t.Errorf("%s %v: %v", code, det, err)
	}
}

func TestPlatformInstalled3x(t *testing.T) {
	dest := t.TempDir()
	for _, f := range []string{"iphone.zip", "osx.zip", "webassembly_debug.zip", "linux_x11_64_debug", "windows_64_debug.exe"} {
		os.WriteFile(filepath.Join(dest, f), nil, 0o644)
	}
	got := installedPlatforms(dest)
	if strings.Join(got, ",") != "ios,linux,macos,web,windows" {
		t.Errorf("plataformas 3.x: %v", got)
	}
}

func TestUnixGodotDir(t *testing.T) {
	data := t.TempDir()
	legacy := filepath.Join(t.TempDir(), "godot")
	if got, want := unixGodotDir(legacy, data), filepath.Join(data, "godot-manager"); got != want {
		t.Errorf("sin %s: %s, quiero %s", legacy, got, want)
	}
	if err := os.Mkdir(legacy, 0o755); err != nil {
		t.Fatal(err)
	}
	if got := unixGodotDir(legacy, data); got != legacy {
		t.Errorf("con %s: %s", legacy, got)
	}
}
