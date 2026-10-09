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
ICONS="$HOME/.local/share/icons/hicolor/scalable/apps"
mkdir -p "$ICONS"
install -m644 "$REPO_DIR/packaging/fatal-lyrics.svg" "$ICONS/fatal-lyrics.svg"
command -v update-desktop-database >/dev/null && update-desktop-database "$HOME/.local/share/applications"

# autostart: unit de usuario, habilitada pero sin --now (no pisa una instancia que ya corre)
if command -v systemctl >/dev/null && systemctl --user show-environment >/dev/null 2>&1; then
    UNITS="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    mkdir -p "$UNITS"
    sed "s|^ExecStart=/usr/bin/fatal|ExecStart=$HOME/.local/bin/fatal|" \
        "$REPO_DIR/packaging/fatal-lyrics.service" > "$UNITS/fatal-lyrics.service"
    systemctl --user daemon-reload
    systemctl --user enable fatal-lyrics.service
fi

# clean up legacy symlinks from older versions
[ -L "$HOME/.config/quickshell/cartelitos" ] && rm "$HOME/.config/quickshell/cartelitos"
[ -L "$HOME/.local/bin/cartelitos" ] && rm "$HOME/.local/bin/cartelitos"
[ -f "$HOME/.local/share/applications/cartelitos.desktop" ] && rm "$HOME/.local/share/applications/cartelitos.desktop"

echo "installed. Play something on Spotify and run: fatal"
echo "config: auto-created at ~/.config/cartelitos/config.toml (every option: fatal ajustes)"
if command -v hyprctl >/dev/null && [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua" ]; then
    echo "Hyprland (Lua config): keybinds + layer rule live in packaging/hyprland.lua; load it from hyprland.lua with"
    echo "    dofile(\"$REPO_DIR/packaging/hyprland.lua\")"
fi
echo "system tray (icon + quit button): optional, install gtk3 + libayatana-appindicator"
