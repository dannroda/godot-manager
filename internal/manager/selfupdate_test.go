package manager

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestIsNewerVersion(t *testing.T) {
	cases := []struct {
		latest, current string
		want            bool
	}{
		{"2.3.0", "2.2.0", true},
		{"v2.3.0", "v2.2.0", true},
		{"2.2.0", "2.2.0", false},
		{"2.2.0", "2.3.0", false},
		{"2.10.0", "2.9.1", true},
		{"3.0", "2.9.9", true},
		{"2.3.0", "2.3.0-rc1", true},
		{"2.2.0", "v2.2.0-3-gabc123", false},
		{"2.3.0", "v2.2.0-3-gabc123", true},
		{"2.3.0", "dev", false},
		{"2.3.0", "abc1234", false},
	}
	for _, c := range cases {
		if got := isNewerVersion(c.latest, c.current); got != c.want {
			t.Errorf("isNewerVersion(%q, %q) = %v", c.latest, c.current, got)
		}
	}
}

func TestPackageManager(t *testing.T) {
	cases := []struct{ goos, dir, want string }{
		{"linux", "/usr/bin", "el gestor de paquetes"},
		{"linux", "/home/u/godot-manager", ""},
		{"linux", "/usr/local/bin", ""},
		{"darwin", "/opt/homebrew/Cellar/godot-manager/2.4.0/bin", "Homebrew"},
		{"darwin", "/usr/local/Cellar/godot-manager/2.4.0/bin", "Homebrew"},
		{"darwin", "/Users/u/bin", ""},
		{"windows", `C:\Users\u\scoop\apps\godot-manager\2.4.0`, "Scoop"},
		{"windows", `C:\Users\u\godot-manager`, ""},
	}
	for _, c := range cases {
		if got := packageManager(c.goos, c.dir); got != c.want {
			t.Errorf("packageManager(%s, %s) = %q, quiero %q", c.goos, c.dir, got, c.want)
		}
	}
}

// Paquete de release con files (nombre -> contenido) dentro de una carpeta,
// como lo arma release.yml.
func selfArchive(t *testing.T, name string, files map[string]string) []byte {
	t.Helper()
	var buf bytes.Buffer
	top := strings.TrimSuffix(strings.TrimSuffix(name, ".zip"), ".tar.gz") + "/"
	if strings.HasSuffix(name, ".zip") {
		zw := zip.NewWriter(&buf)
		for n, body := range files {
			w, _ := zw.Create(top + n)
			w.Write([]byte(body))
		}
		zw.Close()
		return buf.Bytes()
	}
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	tw.WriteHeader(&tar.Header{Name: top, Typeflag: tar.TypeDir, Mode: 0o755})
	for n, body := range files {
		tw.WriteHeader(&tar.Header{Name: top + n, Typeflag: tar.TypeReg, Mode: 0o755, Size: int64(len(body))})
		tw.Write([]byte(body))
	}
	tw.Close()
	gz.Close()
	return buf.Bytes()
}

type fakeSelfRelease struct {
	srv      *httptest.Server
	dir      string // carpeta "instalada"
	archive  []byte
	sums     string
	octetHit bool
}

func setupSelfUpdate(t *testing.T, tag string, files map[string]string) *fakeSelfRelease {
	t.Helper()
	f := &fakeSelfRelease{dir: t.TempDir()}
	name := selfAssetName(runtime.GOOS, runtime.GOARCH)
	f.archive = selfArchive(t, name, files)
	sum := sha256.Sum256(f.archive)
	f.sums = hex.EncodeToString(sum[:]) + "  " + name + "\n"
	mux := http.NewServeMux()
	f.srv = httptest.NewServer(mux)
	t.Cleanup(f.srv.Close)
	mux.HandleFunc("/repos/self/releases/latest", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{
			"tag_name": tag, "html_url": "https://example.com/" + tag,
			"assets": []map[string]any{
				{"name": name, "url": f.srv.URL + "/assets/1", "size": len(f.archive)},
				{"name": "SHA256SUMS", "url": f.srv.URL + "/assets/2"},
			},
		})
	})
	mux.HandleFunc("/assets/1", func(w http.ResponseWriter, r *http.Request) {
		f.octetHit = r.Header.Get("Accept") == "application/octet-stream"
		w.Write(f.archive)
	})
	mux.HandleFunc("/assets/2", func(w http.ResponseWriter, r *http.Request) { w.Write([]byte(f.sums)) })

	oldSelf, oldAPI, oldExe, oldVersion := selfAPI, githubAPI, selfExecutable, Version
	selfAPI = f.srv.URL + "/repos/self"
	githubAPI = f.srv.URL + "/repos/builds"
	exe := filepath.Join(f.dir, exeFile("godot-manager"))
	selfExecutable = func() (string, error) { return exe, nil }
	Version = "2.2.0"
	t.Cleanup(func() { selfAPI, githubAPI, selfExecutable, Version = oldSelf, oldAPI, oldExe, oldVersion })
	return f
}

func exeFile(name string) string {
	if runtime.GOOS == "windows" {
		return name + ".exe"
	}
	return name
}

func uiFile() string {
	if runtime.GOOS == "windows" {
		return "godot-manager-ui.exe"
	}
	return "godot-manager-ui.x86_64"
}

func TestSelfUpdate(t *testing.T) {
	f := setupSelfUpdate(t, "v2.3.0", map[string]string{
		exeFile("godot-manager"): "gm nuevo", exeFile("godot"): "godot nuevo",
		uiFile(): "ui nueva", "README.md": "readme", "LICENSE": "mit",
	})
	writeFiles(t, f.dir, map[string]string{
		exeFile("godot-manager"): "gm viejo", exeFile("godot"): "godot viejo", uiFile(): "ui vieja",
	})

	info, err := checkUpdate()
	if err != nil {
		t.Fatal(err)
	}
	if !info.UpdateAvailable || !info.CanUpdate || info.Latest != "2.3.0" || info.Dir != f.dir {
		t.Fatalf("%+v", info)
	}

	defer func(v bool) { assumeYes = v }(assumeYes)
	assumeYes = true
	res, err := cmdSelfUpdate(nil)
	if err != nil {
		t.Fatal(err)
	}
	if res["updated"] != true || res["version"] != "2.3.0" {
		t.Errorf("res: %v", res)
	}
	if !f.octetHit {
		t.Error("el asset no se pidio como octet-stream")
	}
	for name, want := range map[string]string{exeFile("godot-manager"): "gm nuevo", exeFile("godot"): "godot nuevo", uiFile(): "ui nueva"} {
		if got := readFile(t, filepath.Join(f.dir, name)); got != want {
			t.Errorf("%s = %q", name, got)
		}
		if _, err := os.Stat(filepath.Join(f.dir, name+".old")); err == nil {
			t.Errorf("quedo %s.old", name)
		}
	}
	// Lo que no estaba instalado no se agrega.
	for _, name := range []string{"README.md", "LICENSE"} {
		if _, err := os.Stat(filepath.Join(f.dir, name)); err == nil {
			t.Errorf("agrego %s", name)
		}
	}
	ents, _ := os.ReadDir(f.dir)
	if len(ents) != 3 {
		t.Errorf("sobran archivos: %v", ents)
	}
}

func TestSelfUpdateUpToDateAndChecksum(t *testing.T) {
	f := setupSelfUpdate(t, "v2.2.0", map[string]string{exeFile("godot-manager"): "x"})
	writeFiles(t, f.dir, map[string]string{exeFile("godot-manager"): "viejo"})
	res, err := cmdSelfUpdate(nil)
	if err != nil || res["updated"] != false {
		t.Fatalf("al dia: %v %v", res, err)
	}

	f = setupSelfUpdate(t, "v9.0.0", map[string]string{exeFile("godot-manager"): "x"})
	writeFiles(t, f.dir, map[string]string{exeFile("godot-manager"): "viejo"})
	f.sums = strings.Repeat("0", 64) + "  " + selfAssetName(runtime.GOOS, runtime.GOARCH) + "\n"
	defer func(v bool) { assumeYes = v }(assumeYes)
	assumeYes = true
	_, err = cmdSelfUpdate(nil)
	if code, _ := errorInfo(err); code != codeChecksum {
		t.Fatalf("checksum: %v", err)
	}
	if got := readFile(t, filepath.Join(f.dir, exeFile("godot-manager"))); got != "viejo" {
		t.Errorf("toco el binario: %q", got)
	}
}

func TestSelfUpdateCannot(t *testing.T) {
	f := setupSelfUpdate(t, "v9.0.0", map[string]string{exeFile("godot-manager"): "x"})
	Version = "dev"
	info, err := checkUpdate()
	if err != nil {
		t.Fatal(err)
	}
	if info.UpdateAvailable || info.CanUpdate || !strings.Contains(info.Reason, "desarrollo") {
		t.Errorf("dev: %+v", info)
	}
	Version = "2.2.0"
	if runtime.GOOS != "windows" {
		selfExecutable = func() (string, error) { return "/usr/bin/godot-manager", nil }
		info, _ = checkUpdate()
		if info.CanUpdate || !strings.Contains(info.Reason, "gestor de paquetes") {
			t.Errorf("/usr/bin: %+v", info)
		}
		_, err = cmdSelfUpdate(nil)
		if code, _ := errorInfo(err); code != codeCannotSelfUpdate {
			t.Errorf("sin poder: %v", err)
		}
	}
	_ = f
}
