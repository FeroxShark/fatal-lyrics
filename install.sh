#!/bin/bash
# fatal-lyrics — manual installer (no AUR): symlinks the launcher into ~/.local/bin
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

missing=0
for dep in qs playerctl python3; do
    if ! command -v "$dep" >/dev/null; then
        echo "missing dependency: $dep"
        missing=1
    fi
done
[ "$missing" -eq 1 ] && exit 1

mkdir -p "$HOME/.local/bin"
ln -sf "$REPO_DIR/bin/fatal" "$HOME/.local/bin/fatal"
chmod +x "$REPO_DIR/bin/fatal" "$REPO_DIR/cartelitos.py"

mkdir -p "$HOME/.local/share/applications"
sed "s|Exec=fatal|Exec=$HOME/.local/bin/fatal|" "$REPO_DIR/packaging/fatal.desktop" \
    > "$HOME/.local/share/applications/fatal.desktop"
command -v update-desktop-database >/dev/null && update-desktop-database "$HOME/.local/share/applications"

# clean up legacy symlinks from older versions
[ -L "$HOME/.config/quickshell/cartelitos" ] && rm "$HOME/.config/quickshell/cartelitos"
[ -L "$HOME/.local/bin/cartelitos" ] && rm "$HOME/.local/bin/cartelitos"
[ -f "$HOME/.local/share/applications/cartelitos.desktop" ] && rm "$HOME/.local/share/applications/cartelitos.desktop"

echo "installed. Play something on Spotify and run: fatal"
echo "config: auto-created at ~/.config/cartelitos/config.toml (edit with: fatal config)"
echo "system tray (icon + quit button): optional, install gtk3 + libayatana-appindicator"
