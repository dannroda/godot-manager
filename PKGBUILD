# Maintainer: Dann Roda <contact@dann.com.ar>
pkgname=godot-manager
pkgver=2.3.0
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
}
