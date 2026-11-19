//go:build ignore

// Actualiza los paquetes a una release publicada:
//
//	go run tools/packaging.go v2.4.0
//
//   - packaging/arch/: PKGBUILD de godot-manager-bin (los binarios de la release
//     y la interfaz, para makepkg), con el .desktop y el icono.
//   - bucket/godot-manager.json: manifest de Scoop.
//
// Toma los checksums del SHA256SUMS de la release. Lo corre el workflow
// packaging.yml al publicar una release; tambien sirve a mano.
package main

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"text/template"
)

const repo = "dannroda/godot-manager"

func fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}

func releaseSums(tag string) (map[string]string, error) {
	u := "https://github.com/" + repo + "/releases/download/" + tag + "/SHA256SUMS"
	resp, err := http.Get(u)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("%s: HTTP %d", u, resp.StatusCode)
	}
	sums := map[string]string{}
	sc := bufio.NewScanner(resp.Body)
	for sc.Scan() {
		if f := strings.Fields(sc.Text()); len(f) == 2 {
			sums[strings.TrimPrefix(f[1], "*")] = f[0]
		}
	}
	return sums, sc.Err()
}

func fileSum(p string) string {
	b, err := os.ReadFile(p)
	if err != nil {
		fail(err)
	}
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}

type data struct {
	Version, Desktop, Icon, AMD64, ARM64 string
}

var pkgbuild = template.Must(template.New("").Parse(`# Maintainer: Dann Roda <contact@dann.com.ar>
#
# Generado por tools/packaging.go en github.com/` + repo + `: no editar a mano.
pkgname=godot-manager-bin
pkgver={{.Version}}
pkgrel=1
pkgdesc="Godot version manager: installs official builds, export templates and debug symbols, and picks the version per project"
arch=('x86_64' 'aarch64')
url="https://github.com/` + repo + `"
license=('MIT')
provides=('godot-manager' 'godot')
conflicts=('godot-manager' 'godot' 'godot-mono')
optdepends=('gdb: debug symbols (godot-manager symbols)')
options=('!strip' '!debug')
source=('godot-manager.desktop' 'godot-manager.svg')
source_x86_64=("godot-manager-$pkgver-x86_64.tar.gz::$url/releases/download/v$pkgver/godot-manager-linux-amd64.tar.gz")
source_aarch64=("godot-manager-$pkgver-aarch64.tar.gz::$url/releases/download/v$pkgver/godot-manager-linux-arm64.tar.gz")
sha256sums=('{{.Desktop}}'
            '{{.Icon}}')
sha256sums_x86_64=('{{.AMD64}}')
sha256sums_aarch64=('{{.ARM64}}')

package() {
    local d=godot-manager-linux-amd64
    [[ $CARCH == aarch64 ]] && d=godot-manager-linux-arm64

    install -Dm755 "$d/godot-manager" "$pkgdir/usr/bin/godot-manager"
    install -Dm755 "$d/godot" "$pkgdir/usr/bin/godot"
    install -Dm644 "$d/LICENSE" "$pkgdir/usr/share/licenses/$pkgname/LICENSE"

    # la interfaz solo viene para x86_64
    if [[ -f $d/godot-manager-ui.x86_64 ]]; then
        install -Dm755 "$d/godot-manager-ui.x86_64" "$pkgdir/usr/bin/godot-manager-ui"
        install -Dm644 godot-manager.desktop "$pkgdir/usr/share/applications/godot-manager.desktop"
        install -Dm644 godot-manager.svg "$pkgdir/usr/share/icons/hicolor/scalable/apps/godot-manager.svg"
    fi

    # 'completion' existe desde 2.4.0
    local gm="$pkgdir/usr/bin/godot-manager"
    if "$gm" completion bash >/dev/null 2>&1; then
        "$gm" completion bash | install -Dm644 /dev/stdin "$pkgdir/usr/share/bash-completion/completions/godot-manager"
        "$gm" completion zsh | install -Dm644 /dev/stdin "$pkgdir/usr/share/zsh/site-functions/_godot-manager"
        "$gm" completion fish | install -Dm644 /dev/stdin "$pkgdir/usr/share/fish/vendor_completions.d/godot-manager.fish"
    fi
}
`))

func writeTemplate(t *template.Template, path string, d data) {
	f, err := os.Create(path)
	if err != nil {
		fail(err)
	}
	if err := t.Execute(f, d); err != nil {
		fail(err)
	}
	if err := f.Close(); err != nil {
		fail(err)
	}
}

func scoopManifest(ver string, sums map[string]string) any {
	dl := "https://github.com/" + repo + "/releases/download/"
	arch := func(goarch, v string) map[string]any {
		name := "godot-manager-windows-" + goarch
		m := map[string]any{"url": dl + v + "/" + name + ".zip", "extract_dir": name}
		if v == "v$version" { // autoupdate: el hash sale del SHA256SUMS
			return m
		}
		m["hash"] = sums[name+".zip"]
		if goarch == "amd64" { // la interfaz solo viene para x86_64
			m["shortcuts"] = [][]string{{"godot-manager-ui.exe", "Godot Manager"}}
		}
		return m
	}
	return map[string]any{
		"version":     ver,
		"description": "Godot version manager: installs official builds, export templates and debug symbols, and picks the version per project.",
		"homepage":    "https://github.com/" + repo,
		"license":     "MIT",
		"architecture": map[string]any{
			"64bit": arch("amd64", "v"+ver),
			"arm64": arch("arm64", "v"+ver),
		},
		"bin":      []string{"godot-manager.exe", "godot.exe"},
		"checkver": map[string]any{"github": "https://github.com/" + repo},
		"autoupdate": map[string]any{
			"architecture": map[string]any{
				"64bit": arch("amd64", "v$version"),
				"arm64": arch("arm64", "v$version"),
			},
			"hash": map[string]any{"url": "$baseurl/SHA256SUMS"},
		},
	}
}

func main() {
	if len(os.Args) != 2 || !strings.HasPrefix(os.Args[1], "v") {
		fail(fmt.Errorf("uso: go run tools/packaging.go vX.Y.Z"))
	}
	tag := os.Args[1]
	ver := strings.TrimPrefix(tag, "v")
	if strings.Contains(ver, "-") {
		fail(fmt.Errorf("%s es una pre-release: los paquetes siguen solo las estables", tag))
	}
	sums, err := releaseSums(tag)
	if err != nil {
		fail(err)
	}
	arch := filepath.Join("packaging", "arch")
	icon, err := os.ReadFile(filepath.Join("ui", "icon.svg"))
	if err != nil {
		fail(err)
	}
	if err := os.WriteFile(filepath.Join(arch, "godot-manager.svg"), icon, 0o644); err != nil {
		fail(err)
	}
	d := data{
		Version: ver,
		Desktop: fileSum(filepath.Join(arch, "godot-manager.desktop")),
		Icon:    fileSum(filepath.Join(arch, "godot-manager.svg")),
		AMD64:   sums["godot-manager-linux-amd64.tar.gz"],
		ARM64:   sums["godot-manager-linux-arm64.tar.gz"],
	}
	for k, v := range map[string]string{"linux-amd64": d.AMD64, "linux-arm64": d.ARM64,
		"windows-amd64": sums["godot-manager-windows-amd64.zip"], "windows-arm64": sums["godot-manager-windows-arm64.zip"]} {
		if v == "" {
			fail(fmt.Errorf("SHA256SUMS de %s no tiene %s", tag, k))
		}
	}
	writeTemplate(pkgbuild, filepath.Join(arch, "PKGBUILD"), d)

	b, err := json.MarshalIndent(scoopManifest(ver, sums), "", "    ")
	if err != nil {
		fail(err)
	}
	if err := os.WriteFile(filepath.Join("bucket", "godot-manager.json"), append(b, '\n'), 0o644); err != nil {
		fail(err)
	}
	fmt.Printf("paquetes en %s\n", ver)
}
