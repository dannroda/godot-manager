//go:build ignore

// Genera los rsrc_windows_<arch>.syso de cmd/godot-manager y cmd/godot con
// el icono de ui/icon.ico, para que los .exe lo muestren en el Explorador.
// Go enlaza solo los .syso de la carpeta del paquete al compilar para
// windows. Correr desde la raiz del repo despues de cambiar el icono:
//
//	go run tools/winres.go
//
// Un .syso es un objeto COFF con una seccion .rsrc: el arbol de recursos de
// Windows (RT_ICON por cada imagen y un RT_GROUP_ICON que las agrupa) y una
// relocacion por cada dato, porque el arbol guarda direcciones relativas a la
// imagen y solo el linker sabe donde queda la seccion.
package main

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"os"
	"path/filepath"
	"sort"
)

const (
	rtIcon      = 3
	rtGroupIcon = 14
	langNeutral = 0
)

type icoImage struct {
	width, height, colors uint8
	planes, bitCount      uint16
	data                  []byte
}

func readICO(path string) ([]icoImage, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	le := binary.LittleEndian
	if len(b) < 6 || le.Uint16(b[2:]) != 1 {
		return nil, fmt.Errorf("%s no es un .ico", path)
	}
	n := int(le.Uint16(b[4:]))
	var imgs []icoImage
	for i := range n {
		e := b[6+16*i:]
		size, off := le.Uint32(e[8:]), le.Uint32(e[12:])
		imgs = append(imgs, icoImage{
			width: e[0], height: e[1], colors: e[2],
			planes: le.Uint16(e[4:]), bitCount: le.Uint16(e[6:]),
			data: b[off : off+size],
		})
	}
	return imgs, nil
}

// Recurso: tipo, id y datos (idioma neutro).
type resource struct {
	typ, id uint16
	data    []byte
}

// Seccion .rsrc: directorio raiz -> tipos -> ids -> idioma -> dato. Devuelve
// los bytes y la posicion de cada campo OffsetToData (a relocar).
func buildRsrc(res []resource) ([]byte, []uint32) {
	sort.Slice(res, func(i, j int) bool {
		if res[i].typ != res[j].typ {
			return res[i].typ < res[j].typ
		}
		return res[i].id < res[j].id
	})
	byType := map[uint16][]resource{}
	var types []uint16
	for _, r := range res {
		if len(byType[r.typ]) == 0 {
			types = append(types, r.typ)
		}
		byType[r.typ] = append(byType[r.typ], r)
	}
	dirSize := func(n int) int { return 16 + 8*n }

	// primero todos los directorios, despues las entradas de datos, despues
	// los datos
	off := dirSize(len(types))
	typeDir := map[uint16]int{}
	for _, t := range types {
		typeDir[t] = off
		off += dirSize(len(byType[t]))
	}
	langDir := map[[2]uint16]int{}
	for _, t := range types {
		for _, r := range byType[t] {
			langDir[[2]uint16{t, r.id}] = off
			off += dirSize(1)
		}
	}
	entry := map[[2]uint16]int{}
	for _, t := range types {
		for _, r := range byType[t] {
			entry[[2]uint16{t, r.id}] = off
			off += 16
		}
	}
	dataOff := map[[2]uint16]int{}
	for _, t := range types {
		for _, r := range byType[t] {
			off = (off + 7) &^ 7
			dataOff[[2]uint16{t, r.id}] = off
			off += len(r.data)
		}
	}

	buf := make([]byte, off)
	le := binary.LittleEndian
	dir := func(at, n int) {
		le.PutUint16(buf[at+14:], uint16(n)) // NumberOfIdEntries
	}
	dirEntry := func(at, i int, id uint32, target int, sub bool) {
		p := at + 16 + 8*i
		le.PutUint32(buf[p:], id)
		v := uint32(target)
		if sub {
			v |= 0x80000000
		}
		le.PutUint32(buf[p+4:], v)
	}
	dir(0, len(types))
	var relocs []uint32
	for i, t := range types {
		dirEntry(0, i, uint32(t), typeDir[t], true)
		dir(typeDir[t], len(byType[t]))
		for j, r := range byType[t] {
			k := [2]uint16{t, r.id}
			dirEntry(typeDir[t], j, uint32(r.id), langDir[k], true)
			dir(langDir[k], 1)
			dirEntry(langDir[k], 0, langNeutral, entry[k], false)
			le.PutUint32(buf[entry[k]:], uint32(dataOff[k])) // OffsetToData (RVA)
			le.PutUint32(buf[entry[k]+4:], uint32(len(r.data)))
			relocs = append(relocs, uint32(entry[k]))
			copy(buf[dataOff[k]:], r.data)
		}
	}
	return buf, relocs
}

// Objeto COFF con la seccion .rsrc y su simbolo.
func coff(machine uint16, relocType uint16, rsrc []byte, relocs []uint32) []byte {
	var b bytes.Buffer
	le := binary.LittleEndian
	const headers = 20 + 40
	rawPtr := uint32(headers)
	relocPtr := rawPtr + uint32(len(rsrc))
	symPtr := relocPtr + uint32(10*len(relocs))

	w := func(v any) { binary.Write(&b, le, v) }
	// IMAGE_FILE_HEADER
	w(machine)
	w(uint16(1)) // secciones
	w(uint32(0)) // fecha: 0, asi el archivo no cambia si el icono no cambia
	w(symPtr)
	w(uint32(1)) // simbolos
	w(uint16(0))
	w(uint16(0))
	// IMAGE_SECTION_HEADER
	b.WriteString(".rsrc\x00\x00\x00")
	w(uint32(0))
	w(uint32(0))
	w(uint32(len(rsrc)))
	w(rawPtr)
	w(relocPtr)
	w(uint32(0))
	w(uint16(len(relocs)))
	w(uint16(0))
	w(uint32(0x40000040)) // INITIALIZED_DATA | MEM_READ
	b.Write(rsrc)
	for _, r := range relocs {
		w(r)
		w(uint32(0)) // simbolo 0: la seccion
		w(relocType)
	}
	// simbolo de la seccion
	b.WriteString(".rsrc\x00\x00\x00")
	w(uint32(0))
	w(int16(1)) // seccion 1
	w(uint16(0))
	w(uint8(3)) // IMAGE_SYM_CLASS_STATIC
	w(uint8(0))
	w(uint32(4)) // tabla de strings vacia
	return b.Bytes()
}

func main() {
	imgs, err := readICO("ui/icon.ico")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	var res []resource
	var group bytes.Buffer
	le := binary.LittleEndian
	binary.Write(&group, le, [3]uint16{0, 1, uint16(len(imgs))})
	for i, img := range imgs {
		id := uint16(i + 1)
		res = append(res, resource{rtIcon, id, img.data})
		group.Write([]byte{img.width, img.height, img.colors, 0})
		binary.Write(&group, le, img.planes)
		binary.Write(&group, le, img.bitCount)
		binary.Write(&group, le, uint32(len(img.data)))
		binary.Write(&group, le, id)
	}
	// id 1: el que muestra el Explorador (el primer grupo)
	res = append(res, resource{rtGroupIcon, 1, group.Bytes()})
	rsrc, relocs := buildRsrc(res)

	archs := []struct {
		name           string
		machine, reloc uint16
	}{
		{"amd64", 0x8664, 0x0003}, // IMAGE_REL_AMD64_ADDR32NB
		{"arm64", 0xaa64, 0x0002}, // IMAGE_REL_ARM64_ADDR32NB
	}
	for _, dir := range []string{"cmd/godot-manager", "cmd/godot"} {
		for _, a := range archs {
			p := filepath.Join(dir, "rsrc_windows_"+a.name+".syso")
			if err := os.WriteFile(p, coff(a.machine, a.reloc, rsrc, relocs), 0o644); err != nil {
				fmt.Fprintln(os.Stderr, err)
				os.Exit(1)
			}
			fmt.Println(p)
		}
	}
}
