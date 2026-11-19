# Maintainer: Dann Roda <contact@dann.com.ar>
#
# Compila el CLI desde este checkout (makepkg -si). El paquete con los
# binarios de la release y la interfaz es godot-manager-bin (packaging/aur).
pkgname=godot-manager
pkgver=2.3.1
pkgrel=1
pkgdesc="Instala y selecciona versiones de Godot (stable, dev, mono, export templates, simbolos de debug) por proyecto"
arch=('x86_64' 'aarch64')
license=('MIT')
makedepends=('go')
optdepends=('gdb: usar los simbolos de debug (godot-manager symbols)')
provides=('godot')
conflicts=('godot' 'godot-mono')

build() {
    cd "$startdir"
    export CGO_ENABLED=0
    export GOFLAGS="-trimpath -mod=readonly -modcacherw"
    go build -ldflags "-X main.version=$pkgver" -o "$srcdir/" ./cmd/...
}

package() {
    install -Dm755 "$srcdir/godot-manager" "$pkgdir/usr/bin/godot-manager"
    install -Dm755 "$srcdir/godot" "$pkgdir/usr/bin/godot"
    install -Dm644 "$startdir/LICENSE" "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
    local gm="$srcdir/godot-manager"
    "$gm" completion bash | install -Dm644 /dev/stdin "$pkgdir/usr/share/bash-completion/completions/godot-manager"
    "$gm" completion zsh | install -Dm644 /dev/stdin "$pkgdir/usr/share/zsh/site-functions/_godot-manager"
    "$gm" completion fish | install -Dm644 /dev/stdin "$pkgdir/usr/share/fish/vendor_completions.d/godot-manager.fish"
}
