#!/bin/bash
# fatal-lyrics — instalador: symlinks a ~/.config/quickshell y ~/.local/bin
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

missing=0
for dep in qs playerctl python3; do
    if ! command -v "$dep" >/dev/null; then
        echo "falta dependencia: $dep"
        missing=1
    fi
done
[ "$missing" -eq 1 ] && exit 1

mkdir -p "$HOME/.config/quickshell" "$HOME/.local/bin"
ln -sfn "$REPO_DIR/shell" "$HOME/.config/quickshell/cartelitos"
ln -sf "$REPO_DIR/bin/cartelitos" "$HOME/.local/bin/cartelitos"
chmod +x "$REPO_DIR/bin/cartelitos" "$REPO_DIR/cartelitos.py"

echo "instalado. Poné música en Spotify y corré: cartelitos"
echo "(si tu monitor no es DP-6, editá targetScreen en shell/shell.qml)"
