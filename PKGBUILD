# Maintainer: Dann Roda <contact@dann.com.ar>
pkgname=godot-manager
pkgver=1.1.0
pkgrel=1
pkgdesc="Instala y selecciona versiones de Godot (stable, dev, mono, simbolos de debug) por proyecto"
arch=('any')
license=('unknown')
depends=('bash' 'coreutils' 'curl' 'wget' 'jq' 'unzip' 'findutils')
optdepends=('gdb: usar los simbolos de debug (godot-manager symbols)')
provides=('godot')
conflicts=('godot' 'godot-mono')
source=('godot-manager' 'godot')
sha256sums=('SKIP' 'SKIP')

package() {
    install -Dm755 "$srcdir/godot-manager" "$pkgdir/usr/bin/godot-manager"
    install -Dm755 "$srcdir/godot" "$pkgdir/usr/bin/godot"
}
