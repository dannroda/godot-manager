# Binarios para distribuir fuera de Arch: dist/<os>-<arch>/{godot-manager,godot}[.exe]
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
TARGETS := linux/amd64 linux/arm64 windows/amd64 windows/arm64 darwin/amd64 darwin/arm64

.PHONY: build dist clean
build:
	CGO_ENABLED=0 go build -trimpath -ldflags "-X main.version=$(VERSION)" -o bin/ ./cmd/...

dist:
	@for t in $(TARGETS); do \
		os=$${t%/*}; arch=$${t#*/}; \
		echo "$$os-$$arch"; \
		CGO_ENABLED=0 GOOS=$$os GOARCH=$$arch go build -trimpath \
			-ldflags "-X main.version=$(VERSION)" -o dist/$$os-$$arch/ ./cmd/... || exit 1; \
	done

clean:
	rm -rf bin dist
