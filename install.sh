#!/bin/bash
# fatal-lyrics — instalador manual (sin AUR): symlink del launcher a ~/.local/bin
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

mkdir -p "$HOME/.local/bin"
ln -sf "$REPO_DIR/bin/cartelitos" "$HOME/.local/bin/cartelitos"
chmod +x "$REPO_DIR/bin/cartelitos" "$REPO_DIR/cartelitos.py"

mkdir -p "$HOME/.local/share/applications"
sed "s|Exec=cartelitos|Exec=$HOME/.local/bin/cartelitos|" "$REPO_DIR/packaging/cartelitos.desktop" \
    > "$HOME/.local/share/applications/cartelitos.desktop"
command -v update-desktop-database >/dev/null && update-desktop-database "$HOME/.local/share/applications"

# limpiar symlink legacy de versiones viejas
[ -L "$HOME/.config/quickshell/cartelitos" ] && rm "$HOME/.config/quickshell/cartelitos"

echo "instalado. Poné música en Spotify y corré: cartelitos"
echo "config: se crea sola en ~/.config/cartelitos/config.toml (editar con: cartelitos config)"
echo "bandeja del sistema (ícono + botón cerrar): opcional, instalá gtk3 + libayatana-appindicator"
