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
