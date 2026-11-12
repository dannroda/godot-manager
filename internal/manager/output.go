package manager

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"sync"
	"time"
)

// Como sale lo que imprimen los comandos.
//
//   - modeText: mensajes en stdout, avisos y errores en stderr, barra de
//     progreso en stderr si es una terminal.
//   - modeJSON (--json): solo el resultado final en stdout, como un objeto
//     {"ok":true,...} o {"error":{"code","message",...}}.
//   - modeEvents (--json en install, templates y symbols): un objeto JSON por
//     linea en stdout: step, download y warn mientras trabaja, y al final
//     done o error.
type outMode int

const (
	modeText outMode = iota
	modeJSON
	modeEvents
)

type output struct {
	mode   outMode
	stdout io.Writer
	stderr io.Writer
	mu     sync.Mutex
}

var out = &output{stdout: os.Stdout, stderr: os.Stderr}

func (o *output) isJSON() bool { return o.mode != modeText }

// Lo que va haciendo: texto, o un evento step. Con --json en un comando sin
// eventos no sale nada (solo el resultado).
func (o *output) step(format string, a ...any) {
	msg := fmt.Sprintf(format, a...)
	switch o.mode {
	case modeText:
		fmt.Fprintln(o.stdout, msg)
	case modeEvents:
		o.event("step", map[string]any{"message": msg})
	}
}

func (o *output) warn(format string, a ...any) {
	msg := fmt.Sprintf(format, a...)
	if o.mode == modeEvents {
		o.event("warn", map[string]any{"message": msg})
		return
	}
	fmt.Fprintln(o.stderr, "Aviso: "+msg)
}

func (o *output) event(name string, fields map[string]any) {
	m := map[string]any{"event": name}
	for k, v := range fields {
		m[k] = v
	}
	o.line(m)
}

// Un objeto JSON en una linea de stdout.
func (o *output) line(v any) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		return
	}
	o.mu.Lock()
	defer o.mu.Unlock()
	o.stdout.Write(buf.Bytes())
}

// Resultado de un comando que termino bien (nada en modo texto).
func (o *output) result(fields map[string]any) {
	switch o.mode {
	case modeEvents:
		o.event("done", fields)
	case modeJSON:
		m := map[string]any{"ok": true}
		for k, v := range fields {
			m[k] = v
		}
		o.line(m)
	}
}

func (o *output) fail(err error) {
	code, details := errorInfo(err)
	e := map[string]any{"code": code, "message": err.Error()}
	for k, v := range details {
		e[k] = v
	}
	switch o.mode {
	case modeEvents:
		o.event("error", e)
	case modeJSON:
		o.line(map[string]any{"error": e})
	default:
		fmt.Fprintln(o.stderr, "Error:", err)
	}
}

// Progreso de una descarga: barra en stderr si es una terminal, o eventos
// download (a lo sumo 4 por segundo, mas uno al terminar).
type progress struct {
	total, done int64
	label       string
	last        time.Time
	tty         bool
}

func newProgress(total int64) *progress {
	return &progress{total: total, tty: out.mode == modeText && isTerminal(os.Stderr)}
}

func (p *progress) Write(b []byte) (int, error) {
	p.done += int64(len(b))
	if time.Since(p.last) >= 250*time.Millisecond {
		p.report()
	}
	return len(b), nil
}

func (p *progress) report() {
	p.last = time.Now()
	switch {
	case out.mode == modeEvents:
		out.event("download", map[string]any{"file": p.label, "done": p.done, "total": p.total})
	case p.tty:
		const mb = 1 << 20
		if p.total > 0 {
			fmt.Fprintf(out.stderr, "\r  %6.0f/%.0f MB %3d%%  %-40s",
				float64(p.done)/mb, float64(p.total)/mb, p.done*100/p.total, p.label)
		} else {
			fmt.Fprintf(out.stderr, "\r  %6.0f MB  %-40s", float64(p.done)/mb, p.label)
		}
	}
}

func (p *progress) finish() {
	if out.mode == modeEvents || p.tty {
		p.report()
	}
	if p.tty {
		fmt.Fprintln(out.stderr)
	}
}

func isTerminal(f *os.File) bool {
	fi, err := f.Stat()
	return err == nil && fi.Mode()&os.ModeCharDevice != 0
}
