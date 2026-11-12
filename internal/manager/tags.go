package manager

import (
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

// Tags oficiales: 4.3-stable, 4.8-beta3, 3.6.3-stable, 4.4-dev7, 3.2.3.1-rc2...
var tagRe = regexp.MustCompile(`^(\d+)\.(\d+)(?:\.(\d+))?(?:\.(\d+))?-(dev|alpha|beta|rc|stable)(\d*)$`)

var stageRank = map[string]int{"dev": 0, "alpha": 1, "beta": 2, "rc": 3, "stable": 4}

// Clave para ordenar un tag: 4 numeros de version, etapa y numero de etapa.
func parseTag(tag string) ([6]int, bool) {
	var k [6]int
	m := tagRe.FindStringSubmatch(tag)
	if m == nil {
		return k, false
	}
	for i := range 4 {
		k[i], _ = strconv.Atoi(m[i+1]) // los que faltan quedan en 0
	}
	k[4] = stageRank[m[5]]
	k[5], _ = strconv.Atoi(m[6])
	return k, true
}

// <0, 0 o >0 segun a sea menor, igual o mayor que b como version. Los tags
// que no se entienden van antes que todos.
func compareTags(a, b string) int {
	ka, oka := parseTag(a)
	kb, okb := parseTag(b)
	switch {
	case !oka && !okb:
		return strings.Compare(a, b)
	case !oka:
		return -1
	case !okb:
		return 1
	}
	for i := range ka {
		if ka[i] != kb[i] {
			return ka[i] - kb[i]
		}
	}
	return 0
}

// Marca de una version agregada con 'add' (build propio): no tiene templates
// ni simbolos oficiales.
const customMarker = ".godot-custom"

// Tag de la release de una version instalada (sin -mono), o "" si es custom.
func versionTag(name string) string {
	if exists(filepath.Join(versionsDir, name, customMarker)) {
		return ""
	}
	tag := strings.TrimSuffix(name, "-mono")
	if _, ok := parseTag(tag); !ok {
		return ""
	}
	return tag
}
