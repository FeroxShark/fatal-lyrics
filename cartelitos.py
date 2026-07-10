#!/usr/bin/env python3
"""cartelitos / fatal-lyrics — synced Spotify lyrics as Windows error dialogs.

Follows playback via MPRIS (playerctl), fetches synced lyrics from
lrclib.net, and sends each line to the Quickshell overlay over a Unix
socket. Config at ~/.config/cartelitos/config.toml (auto-created with
defaults).
"""
import json
import os
import re
import socket
import subprocess
import sys
import threading
import time
import tomllib
import urllib.parse
import urllib.request

UA = "fatal-lyrics/1.0 (https://github.com/FeroxShark/fatal-lyrics)"
FIELD_SEP = "\x1f"
POLL = 0.3
SOCK_PATH = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "cartelitos.sock")
CONFIG_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "cartelitos")
CONFIG_PATH = os.path.join(CONFIG_DIR, "config.toml")

DEFAULT_CONFIG = """\
# fatal-lyrics — configuration
# Apply changes with: fatal restart

[display]
screen = "auto"        # "auto" (first monitor) | "all" (every one) | "DP-1" | ["DP-1", "DP-2"]
max_dialogs = 0        # max live dialogs at once; 0 = unlimited
scale = 1.0            # base size for all dialogs
current_scale = 1.3    # extra size factor for the current-line dialog
spawn_area = "full"    # full | top | bottom | left | right | edges (leaves the center clear)
karaoke = false        # current line paints word by word (estimated timing)

[effects]
glitch = "normal"      # off | soft | normal | aggressive
effects_on_current = false  # true = the current dialog also vibrates/glitches
tearing = true         # old dialogs get a split window
death_age_min = 3      # a dialog dies between N…
death_age_max = 7      # …and M dialogs after it appears
max_lifetime = 60      # max lifetime per dialog in seconds; 0 = unlimited
burn_in = true         # dead dialogs leave a fading burnt shadow
cascade = true         # on track change, dialogs die in a chain (CRT domino)

[behavior]
now_playing = true     # vinyl sleeve with album art on track change
np_corner = "top-right"  # where the sleeve docks: top-left | top-right | bottom-left | bottom-right | center
np_margin = 14         # free pixels against the edges (in case of a bar/panel)
np_vinyl = true        # spinning vinyl record peeking out of the sleeve
troll_no = true        # the "No" button duplicates the dialog; false = just closes it
click_through = false  # true = dialogs don't capture the mouse (clicks pass through)
pause_clear = 15       # seconds paused before clearing everything; 0 = never
player = "spotify"     # MPRIS player name (see: playerctl -l)
offset = 0.15          # sync lead time in seconds
game_pause = true      # auto-pause when a window goes fullscreen (generic "game" heuristic
                        # via Hyprland, doesn't depend on a specific process);
                        # false = never pause for games
"""

DEFAULTS = {
    "display": {
        "screen": "auto", "max_dialogs": 0, "scale": 1.0,
        "current_scale": 1.3, "spawn_area": "full", "karaoke": False,
    },
    "effects": {
        "glitch": "normal", "effects_on_current": False, "tearing": True,
        "death_age_min": 3, "death_age_max": 7, "max_lifetime": 60,
        "burn_in": True, "cascade": True,
    },
    "behavior": {
        "now_playing": True, "np_corner": "top-right", "np_margin": 14,
        "np_vinyl": True, "troll_no": True, "click_through": False,
        "pause_clear": 15, "player": "spotify", "offset": 0.15,
        "game_pause": True,
    },
}

TS_RE = re.compile(r"\[(\d+):(\d+(?:\.\d+)?)\]")


def log(*args):
    print(time.strftime("%H:%M:%S"), *args, flush=True)


def load_config():
    if not os.path.exists(CONFIG_PATH):
        os.makedirs(CONFIG_DIR, exist_ok=True)
        with open(CONFIG_PATH, "w") as f:
            f.write(DEFAULT_CONFIG)
        log(f"default config created at {CONFIG_PATH}")
    cfg = {k: dict(v) for k, v in DEFAULTS.items()}
    try:
        with open(CONFIG_PATH, "rb") as f:
            user = tomllib.load(f)
        for section, values in user.items():
            if section in cfg and isinstance(values, dict):
                cfg[section].update(values)
    except Exception as e:
        log(f"invalid config ({e}), using defaults")
    return cfg


CFG = load_config()


def playerctl_state():
    """Devuelve dict con track+posición del player, o None si no hay."""
    fmt = FIELD_SEP.join([
        "{{mpris:trackid}}", "{{title}}", "{{artist}}", "{{album}}",
        "{{mpris:length}}", "{{status}}", "{{position}}", "{{mpris:artUrl}}",
    ])
    try:
        out = subprocess.run(
            ["playerctl", "-p", CFG["behavior"]["player"], "metadata", "--format", fmt],
            capture_output=True, text=True, timeout=3,
        )
    except Exception:
        return None
    if out.returncode != 0:
        return None
    fields = out.stdout.strip("\n").split(FIELD_SEP)
    if len(fields) != 8:
        return None
    tid, title, artist, album, length, status, pos, art = fields
    try:
        return {
            "id": tid,
            "title": title,
            "artist": artist,
            "album": album,
            "length": int(length or 0) / 1e6,
            "status": status,
            "pos": int(pos or 0) / 1e6,
            "art": art,
        }
    except ValueError:
        return None


def gaming():
    """True si hay una ventana en pantalla completa (no molestar). Heurística
    genérica vía Hyprland: no depende de una lista de procesos puntuales, así
    que funciona con cualquier juego que pida fullscreen (no detecta borderless
    windowed, que para Hyprland es una ventana normal)."""
    if not CFG["behavior"]["game_pause"]:
        return False
    try:
        out = subprocess.run(["hyprctl", "activewindow", "-j"],
                             capture_output=True, text=True, timeout=2)
        if out.returncode != 0 or not out.stdout.strip():
            return False
        w = json.loads(out.stdout)
        return bool(w) and (w.get("fullscreen", 0) != 0 or w.get("fullscreenClient", 0) != 0)
    except Exception:
        return False


def parse_lrc(text):
    lines = []
    for raw in text.splitlines():
        stamps = TS_RE.findall(raw)
        if not stamps:
            continue
        content = TS_RE.sub("", raw).strip()
        for mins, secs in stamps:
            lines.append((int(mins) * 60 + float(secs), content))
    lines.sort(key=lambda x: x[0])
    return lines or None


def http_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.load(resp)


def fetch_lyrics(track):
    """Letra sincronizada de lrclib: match exacto y si no, búsqueda."""
    params = urllib.parse.urlencode({
        "artist_name": track["artist"],
        "track_name": track["title"],
        "album_name": track["album"],
        "duration": str(int(round(track["length"]))),
    })
    try:
        data = http_json("https://lrclib.net/api/get?" + params)
        if data.get("syncedLyrics"):
            return parse_lrc(data["syncedLyrics"])
    except Exception:
        pass
    try:
        params = urllib.parse.urlencode({
            "track_name": track["title"],
            "artist_name": track["artist"],
        })
        for data in http_json("https://lrclib.net/api/search?" + params):
            if data.get("syncedLyrics"):
                return parse_lrc(data["syncedLyrics"])
    except Exception:
        pass
    return None


_sock = None
_last_np = None


def _config_event():
    d, e, b = CFG["display"], CFG["effects"], CFG["behavior"]
    return {
        "cmd": "config",
        "screen": d["screen"], "max_dialogs": d["max_dialogs"],
        "scale": d["scale"], "current_scale": d["current_scale"],
        "spawn_area": d["spawn_area"], "karaoke": d["karaoke"],
        "glitch": e["glitch"], "effects_on_current": e["effects_on_current"],
        "tearing": e["tearing"], "death_age_min": e["death_age_min"],
        "death_age_max": e["death_age_max"], "max_lifetime": e["max_lifetime"],
        "burn_in": e["burn_in"], "cascade": e["cascade"],
        "click_through": b["click_through"], "troll_no": b["troll_no"],
        "np_corner": b["np_corner"], "np_margin": b["np_margin"],
        "np_vinyl": b["np_vinyl"],
    }


def send(event):
    """Manda un evento JSON al overlay; en cada reconexión manda la config primero
    y reenvía el último Now Playing (el overlay nuevo arranca sin estado)."""
    global _sock, _last_np
    if event.get("cmd") == "np":
        _last_np = event
    data = (json.dumps(event, ensure_ascii=False) + "\n").encode()
    for _ in range(2):
        try:
            if _sock is None:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.settimeout(2)
                s.connect(SOCK_PATH)
                s.sendall((json.dumps(_config_event(), ensure_ascii=False) + "\n").encode())
                if _last_np is not None and _last_np is not event:
                    s.sendall((json.dumps(_last_np, ensure_ascii=False) + "\n").encode())
                _sock = s
            _sock.sendall(data)
            return
        except Exception:
            try:
                if _sock:
                    _sock.close()
            except Exception:
                pass
            _sock = None


def show(text, title, t0=0.0, t1=0.0):
    # t0/t1: comienzo y fin estimado de la línea, para el karaoke del overlay
    send({"cmd": "show", "text": text, "title": title,
          "t0": round(t0, 2), "t1": round(t1, 2)})


def clear():
    send({"cmd": "clear"})


# --------------------------------------------------------------- setup TUI

def _toml_val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return f'"{v}"'
    if isinstance(v, list):
        return "[" + ", ".join(_toml_val(x) for x in v) + "]"
    return str(v)


def _save_config(changes):
    """Pisa claves puntuales del TOML preservando comentarios y el resto.
    changes: {clave: (sección, valor)} — las claves son únicas en el archivo."""
    with open(CONFIG_PATH) as f:
        lines = f.read().split("\n")
    section = None
    pending = dict(changes)
    key_re = re.compile(r"^(\s*)([a-z_]+)(\s*=\s*)([^#]*?)(\s*#.*)?$")
    for i, line in enumerate(lines):
        s = line.strip()
        if s.startswith("[") and s.endswith("]"):
            section = s[1:-1]
            continue
        m = key_re.match(line)
        if m and m.group(2) in pending and pending[m.group(2)][0] == section:
            _, val = pending.pop(m.group(2))
            lines[i] = f"{m.group(1)}{m.group(2)}{m.group(3)}{_toml_val(val)}{m.group(5) or ''}"
    for key, (sec, val) in pending.items():
        # clave que no estaba: al final de su sección (o en una nueva)
        starts = [i for i, l in enumerate(lines) if l.strip() == f"[{sec}]"]
        if starts:
            end = next((j for j in range(starts[0] + 1, len(lines))
                        if lines[j].strip().startswith("[")), len(lines))
            while end > starts[0] + 1 and not lines[end - 1].strip():
                end -= 1
            lines.insert(end, f"{key} = {_toml_val(val)}")
        else:
            lines += [f"[{sec}]", f"{key} = {_toml_val(val)}", ""]
    with open(CONFIG_PATH, "w") as f:
        f.write("\n".join(lines))


def _players():
    """Players MPRIS detectados vía playerctl; lista vacía si no hay o falta el binario."""
    try:
        out = subprocess.run(["playerctl", "-l"], capture_output=True, text=True, timeout=2)
        if out.returncode == 0:
            return [p.strip() for p in out.stdout.splitlines() if p.strip()]
    except Exception:
        pass
    return []


def _monitors():
    """Monitores conectados vía hyprctl; lista vacía si no es Hyprland."""
    try:
        out = subprocess.run(["hyprctl", "monitors", "-j"],
                             capture_output=True, text=True, timeout=3)
        if out.returncode == 0:
            mons = []
            for m in json.loads(out.stdout):
                shape = "vertical" if m.get("transform", 0) % 2 else "horizontal"
                mons.append((m["name"], f"{m['width']}x{m['height']} {shape}"))
            return mons
    except Exception:
        pass
    return []


def _pick(title, options, current):
    """Numbered menu; enter = keep the current value. options: [(label, value)]."""
    print(f"\n{title}   (now: {current})")
    for i, (label, _) in enumerate(options, 1):
        print(f"  {i}) {label}")
    while True:
        raw = input("> ").strip()
        if not raw:
            return None
        if raw.isdigit() and 1 <= int(raw) <= len(options):
            return options[int(raw) - 1][1]
        print("  pick a number from the list, or enter to keep it")


def _ask_num(title, current, lo, hi):
    print(f"\n{title}   (now: {current}, enter = keep)")
    while True:
        raw = input("> ").strip().replace(",", ".")
        if not raw:
            return None
        try:
            v = float(raw)
            if lo <= v <= hi:
                return v
        except ValueError:
            pass
        print(f"  a number between {lo} and {hi}")


def _ask_int(title, current, lo, hi):
    print(f"\n{title}   (now: {current}, enter = keep)")
    while True:
        raw = input("> ").strip()
        if not raw:
            return None
        try:
            v = int(raw)
            if lo <= v <= hi:
                return v
        except ValueError:
            pass
        print(f"  an integer between {lo} and {hi}")


def _ask_text(title, current):
    print(f"\n{title}   (now: \"{current}\", enter = keep)")
    raw = input("> ").strip()
    return raw or None


def setup():
    """Interactive wizard: asks what matters and writes the TOML."""
    cfg = load_config()
    d, e, b = cfg["display"], cfg["effects"], cfg["behavior"]
    ch = {}
    print("fatal-lyrics — setup. Enter on any question = leave it as is.")

    mons = _monitors()
    opts = [("auto (first monitor)", "auto"), ("all screens", "all")]
    opts += [(f"only {n}  ({info})", n) for n, info in mons]
    if len(mons) > 1:
        opts.append(("several (pick which)", "__multi__"))
    v = _pick("Which screen(s) should dialogs appear on?", opts, d["screen"])
    if v == "__multi__":
        for i, (n, info) in enumerate(mons, 1):
            print(f"  {i}) {n}  ({info})")
        raw = input("comma-separated numbers (e.g. 1,3) > ").strip()
        picked = [mons[int(t) - 1][0] for t in (t.strip() for t in raw.split(","))
                  if t.isdigit() and 1 <= int(t) <= len(mons)]
        if picked:
            ch["screen"] = ("display", picked)
    elif v is not None and v != d["screen"]:
        ch["screen"] = ("display", v)

    v = _pick("Vinyl sleeve (album art on track change)",
              [("yes", True), ("no", False)], b["now_playing"])
    if v is not None and v != b["now_playing"]:
        ch["now_playing"] = ("behavior", v)
    if ch.get("now_playing", (None, b["now_playing"]))[1]:
        v = _pick("Where should the sleeve dock?", [
            ("top-left", "top-left"),
            ("top-right", "top-right"),
            ("bottom-left", "bottom-left"),
            ("bottom-right", "bottom-right"),
            ("always centered (shrinks in place)", "center"),
        ], b["np_corner"])
        if v is not None and v != b["np_corner"]:
            ch["np_corner"] = ("behavior", v)
        v = _ask_int("Sleeve margin against the edges (px)", b["np_margin"], 0, 200)
        if v is not None and v != b["np_margin"]:
            ch["np_margin"] = ("behavior", v)
        v = _pick("Spinning vinyl record peeking out of the sleeve",
                  [("yes", True), ("no", False)], b["np_vinyl"])
        if v is not None and v != b["np_vinyl"]:
            ch["np_vinyl"] = ("behavior", v)

    v = _pick("Karaoke (current line paints word by word)",
              [("yes", True), ("no", False)], d["karaoke"])
    if v is not None and v != d["karaoke"]:
        ch["karaoke"] = ("display", v)

    v = _pick("Glitch intensity", [
        ("off (clean dialogs)", "off"), ("soft", "soft"),
        ("normal", "normal"), ("aggressive (dying GPU)", "aggressive"),
    ], e["glitch"])
    if v is not None and v != e["glitch"]:
        ch["glitch"] = ("effects", v)

    v = _pick("Spawn zone", [
        ("full screen", "full"), ("top", "top"), ("bottom", "bottom"),
        ("left", "left"), ("right", "right"),
        ("edges (leaves the center clear)", "edges"),
    ], d["spawn_area"])
    if v is not None and v != d["spawn_area"]:
        ch["spawn_area"] = ("display", v)

    v = _ask_num("Dialog scale", d["scale"], 0.5, 3.0)
    if v is not None and v != d["scale"]:
        ch["scale"] = ("display", v)

    v = _ask_num("Extra scale for the current-line dialog", d["current_scale"], 0.5, 3.0)
    if v is not None and v != d["current_scale"]:
        ch["current_scale"] = ("display", v)

    v = _ask_int("Max live dialogs at once (0 = unlimited)", d["max_dialogs"], 0, 50)
    if v is not None and v != d["max_dialogs"]:
        ch["max_dialogs"] = ("display", v)

    v = _ask_int("A dialog dies between... (new dialogs after it appears)",
                 e["death_age_min"], 1, 50)
    if v is not None and v != e["death_age_min"]:
        ch["death_age_min"] = ("effects", v)
    v = _ask_int("...and at most (new dialogs)", e["death_age_max"], 1, 50)
    if v is not None and v != e["death_age_max"]:
        ch["death_age_max"] = ("effects", v)

    v = _ask_int("Max lifetime per dialog in seconds (0 = unlimited)", e["max_lifetime"], 0, 600)
    if v is not None and v != e["max_lifetime"]:
        ch["max_lifetime"] = ("effects", v)

    v = _ask_int("Seconds paused before clearing everything (0 = never)", b["pause_clear"], 0, 300)
    if v is not None and v != b["pause_clear"]:
        ch["pause_clear"] = ("behavior", v)

    v = _ask_num("Lyric sync lead time in seconds (can be negative)",
                 b["offset"], -2.0, 2.0)
    if v is not None and v != b["offset"]:
        ch["offset"] = ("behavior", v)

    players = _players()
    if players:
        v = _pick("MPRIS player to follow",
                  [(p, p) for p in players] + [("other (type it in)", "__manual__")], b["player"])
        if v == "__manual__":
            v = _ask_text("Player name (see: playerctl -l)", b["player"])
    else:
        v = _ask_text("MPRIS player to follow (see: playerctl -l)", b["player"])
    if v is not None and v != b["player"]:
        ch["player"] = ("behavior", v)

    for key, sec, label, cur in [
        ("tearing", "effects", "Split window on old dialogs", e["tearing"]),
        ("effects_on_current", "effects", "The current dialog also vibrates/glitches", e["effects_on_current"]),
        ("burn_in", "effects", "Fading burnt shadow when a dialog dies (burn-in)", e["burn_in"]),
        ("cascade", "effects", "Dialogs die in a chain on track change", e["cascade"]),
        ("troll_no", "behavior", 'The "No" button duplicates the dialog', b["troll_no"]),
        ("click_through", "behavior", "Ghost dialogs (clicks pass through)", b["click_through"]),
        ("game_pause", "behavior", "Auto-pause when a game is in fullscreen", b["game_pause"]),
    ]:
        v = _pick(label, [("yes", True), ("no", False)], cur)
        if v is not None and v != cur:
            ch[key] = (sec, v)

    if not ch:
        print("\nNo changes.")
        return
    _save_config(ch)
    print(f"\nSaved to {CONFIG_PATH}:")
    for key, (sec, val) in ch.items():
        print(f"  {sec}.{key} = {_toml_val(val)}")
    raw = input("Restart Fatal Lyrics to apply? [Y/n] > ").strip().lower()
    if raw in ("", "y", "yes", "s", "si", "sí"):
        launcher = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bin", "fatal")
        cmd = [launcher] if os.path.exists(launcher) else ["fatal"]
        subprocess.run(cmd + ["restart"])


def current_line_index(lyrics, pos):
    idx = -1
    for i, (ts, _) in enumerate(lyrics):
        if ts <= pos:
            idx = i
        else:
            break
    return idx


def start_tray():
    """Ícono en la bandeja del sistema mientras el daemon está vivo (StatusNotifierItem
    vía AyatanaAppIndicator3). Opcional: si gtk3/libayatana-appindicator no están
    instalados, el daemon sigue andando igual, sin bandeja."""
    try:
        import gi
        gi.require_version("Gtk", "3.0")
        gi.require_version("AyatanaAppIndicator3", "0.1")
        from gi.repository import Gtk, AyatanaAppIndicator3
    except Exception as e:
        log(f"tray not available ({e}), continuing without an icon")
        return

    def run():
        indicator = AyatanaAppIndicator3.Indicator.new(
            "cartelitos", "dialog-warning",
            AyatanaAppIndicator3.IndicatorCategory.APPLICATION_STATUS)
        indicator.set_status(AyatanaAppIndicator3.IndicatorStatus.ACTIVE)
        indicator.set_title("Fatal Lyrics")

        menu = Gtk.Menu()
        status_item = Gtk.MenuItem(label="Fatal Lyrics active")
        status_item.set_sensitive(False)
        menu.append(status_item)
        menu.append(Gtk.SeparatorMenuItem())
        quit_item = Gtk.MenuItem(label="Quit")
        cartelitos_bin = os.path.expanduser("~/.local/bin/fatal")
        quit_item.connect("activate", lambda *_: subprocess.Popen([cartelitos_bin, "off"]))
        menu.append(quit_item)
        menu.show_all()
        indicator.set_menu(menu)

        Gtk.main()

    threading.Thread(target=run, daemon=True, name="tray").start()


def main():
    track_id = None
    lyrics = None
    idx = -1
    paused_by_game = False
    last_game_check = 0.0
    pause_started = None
    pause_cleared = False
    resend_np = False
    last_pos_sent = 0.0
    pause_clear_s = CFG["behavior"]["pause_clear"]
    offset = CFG["behavior"]["offset"]
    log("fatal-lyrics daemon started")
    start_tray()
    send(_config_event())
    while True:
        # pausa automática si hay un juego corriendo
        now = time.monotonic()
        if now - last_game_check > 5:
            last_game_check = now
            if gaming():
                if not paused_by_game:
                    paused_by_game = True
                    track_id = None
                    lyrics = None
                    idx = -1
                    clear()
                    log("game detected: pausing")
            elif paused_by_game:
                paused_by_game = False
                log("game closed: resuming")
        if paused_by_game:
            time.sleep(2)
            continue

        t = playerctl_state()
        if not t or t["status"] not in ("Playing", "Paused"):
            if track_id is not None:
                clear()
                track_id = None
                lyrics = None
                idx = -1
            time.sleep(1.5)
            continue

        # música en pausa mucho tiempo → limpiar carteles colgados
        if t["status"] == "Paused":
            if pause_started is None:
                pause_started = now
            elif pause_clear_s > 0 and not pause_cleared and now - pause_started > pause_clear_s:
                clear()
                pause_cleared = True
                resend_np = True
                idx = -1
                log("long pause: dialogs cleared")
        else:
            pause_started = None
            pause_cleared = False
            # la pausa larga escondió la funda: al retomar, mostrarla de nuevo
            if resend_np:
                resend_np = False
                if CFG["behavior"]["now_playing"] and t["title"]:
                    send({"cmd": "np", "title": t["title"], "artist": t["artist"],
                          "album": t["album"], "art": t["art"]})

        if t["id"] != track_id:
            track_id = t["id"]
            idx = -1
            clear()
            log(f"track: {t['artist']} — {t['title']}")
            if CFG["behavior"]["now_playing"]:
                send({"cmd": "np", "title": t["title"], "artist": t["artist"],
                      "album": t["album"], "art": t["art"]})
            lyrics = fetch_lyrics(t) if t["title"] else None
            if lyrics:
                log(f"synced lyrics: {len(lyrics)} lines")
            else:
                log("no synced lyrics (no dialogs)")

        # progreso de la canción: barra de la funda + karaoke (1 evento por segundo)
        if ((CFG["behavior"]["now_playing"] or CFG["display"]["karaoke"])
                and t["status"] == "Playing"
                and t["length"] > 0 and now - last_pos_sent >= 1.0):
            last_pos_sent = now
            send({"cmd": "pos", "p": round(t["pos"], 2), "l": round(t["length"], 2)})

        if lyrics and t["status"] == "Playing":
            i = current_line_index(lyrics, t["pos"] + offset)
            if i != idx:
                idx = i
                if i >= 0 and lyrics[i][1]:
                    t1 = lyrics[i + 1][0] if i + 1 < len(lyrics) else lyrics[i][0] + 5
                    show(lyrics[i][1], t["title"], lyrics[i][0], t1)

        time.sleep(POLL)


if __name__ == "__main__":
    if "--setup" in sys.argv[1:]:
        try:
            setup()
        except (KeyboardInterrupt, EOFError):
            print("\nok, bye")
        sys.exit(0)
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
