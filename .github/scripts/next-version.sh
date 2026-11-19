#!/bin/sh
# Imprime la versión que sigue al último tag estable vX.Y.Z (la versión sale de los tags: el
# binario la recibe con -ldflags al compilar). Uso: next-version.sh patch|minor|major|X.Y.Z
set -eu
CURRENT=$(git tag --list 'v*' --sort=-v:refname | sed -n 's/^v\([0-9]*\.[0-9]*\.[0-9]*\)$/\1/p' | head -n 1)
if [ -z "$CURRENT" ]; then
	echo "no vX.Y.Z tag found (fetch-depth: 0?)" >&2
	exit 1
fi
MAJOR=${CURRENT%%.*}
REST=${CURRENT#*.}
MINOR=${REST%%.*}
PATCH=${REST#*.}
case "$1" in
	patch) echo "$MAJOR.$MINOR.$((PATCH + 1))" ;;
	minor) echo "$MAJOR.$((MINOR + 1)).0" ;;
	major) echo "$((MAJOR + 1)).0.0" ;;
	*)
		if ! echo "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'; then
			echo "expected patch, minor, major or X.Y.Z[-suffix], got '$1'" >&2
			exit 1
		fi
		echo "$1"
		;;
esac
