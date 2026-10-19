#!/bin/bash
# fatal-lyrics — manual installer (no AUR): symlinks the launcher into ~/.local/bin
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

missing=0
# Quickshell se llama `qs` en Arch y `quickshell` en las distros que sólo traen ese nombre
if ! command -v qs >/dev/null && ! command -v quickshell >/dev/null; then
    echo "missing dependency: qs (Quickshell; the binary may be called quickshell)"
    missing=1
fi
for dep in playerctl python3; do
    if ! command -v "$dep" >/dev/null; then
        echo "missing dependency: $dep"
        missing=1
    fi
done
# config.py usa tomllib (3.11+): con un python viejo instala bien y el daemon revienta al arrancar
if command -v python3 >/dev/null && ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))'; then
    echo "python3 >= 3.11 needed (config.py uses tomllib), found: $(python3 -V 2>&1)"
    missing=1
fi
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
    echo "    local fl = \"$REPO_DIR/packaging/hyprland.lua\""
    echo "    if io.open(fl) then dofile(fl) end"
fi
# lo opcional que falta y qué función se pierde por cada cosa (la misma lista que
# `fatal status`: pw-record/parec, magick, pactl, hyprctl, bandeja). `|| true`: set -e
echo
python3 "$REPO_DIR/cartelitos.py" --check || true
