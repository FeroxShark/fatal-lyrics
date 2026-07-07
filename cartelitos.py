#!/usr/bin/env python3
"""cartelitos — letras de Spotify sincronizadas como diálogos de error de Windows.

Sigue la reproducción por MPRIS (playerctl), baja letras sincronizadas de
lrclib.net y le manda cada línea al overlay Quickshell (config "cartelitos")
vía IPC. Estilo "Me and Mr Wolf".
"""
import json
import os
import re
import socket
import subprocess
import sys
import time
import urllib.parse
import urllib.request

POLL = 0.3          # segundos entre lecturas de posición
OFFSET = 0.15       # adelanto para compensar latencia de render
UA = "cartelitos/1.0 (uso personal)"
FIELD_SEP = "\x1f"
SOCK_PATH = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "cartelitos.sock")

TS_RE = re.compile(r"\[(\d+):(\d+(?:\.\d+)?)\]")


def log(*args):
    print(time.strftime("%H:%M:%S"), *args, flush=True)


GAME_PROCS = ("cs2",)  # si alguno corre, cartelitos se pausa solo


def playerctl_state():
    """Devuelve dict con track+posición de Spotify, o None si no hay player."""
    fmt = FIELD_SEP.join([
        "{{mpris:trackid}}", "{{title}}", "{{artist}}", "{{album}}",
        "{{mpris:length}}", "{{status}}", "{{position}}", "{{mpris:artUrl}}",
    ])
    try:
        out = subprocess.run(
            ["playerctl", "-p", "spotify", "metadata", "--format", fmt],
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
    """True si hay un juego corriendo (no molestar)."""
    for proc in GAME_PROCS:
        if subprocess.run(["pgrep", "-x", proc], capture_output=True).returncode == 0:
            return True
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


def send(event):
    """Manda un evento JSON al overlay por el socket Unix (reconecta si hace falta)."""
    global _sock
    data = (json.dumps(event, ensure_ascii=False) + "\n").encode()
    for _ in range(2):
        try:
            if _sock is None:
                _sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                _sock.settimeout(2)
                _sock.connect(SOCK_PATH)
            _sock.sendall(data)
            return
        except Exception:
            try:
                if _sock:
                    _sock.close()
            except Exception:
                pass
            _sock = None


def show(text, title):
    send({"cmd": "show", "text": text, "title": title})


def clear():
    send({"cmd": "clear"})


def current_line_index(lyrics, pos):
    idx = -1
    for i, (ts, _) in enumerate(lyrics):
        if ts <= pos:
            idx = i
        else:
            break
    return idx


def main():
    track_id = None
    lyrics = None
    idx = -1
    paused_by_game = False
    last_game_check = 0.0
    log("cartelitos daemon arrancó")
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
                    log("juego detectado: cartelitos en pausa")
            elif paused_by_game:
                paused_by_game = False
                log("juego cerrado: cartelitos vuelve")
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

        if t["id"] != track_id:
            track_id = t["id"]
            idx = -1
            clear()
            log(f"track: {t['artist']} — {t['title']}")
            send({"cmd": "np", "title": t["title"], "artist": t["artist"],
                  "album": t["album"], "art": t["art"]})
            lyrics = fetch_lyrics(t) if t["title"] else None
            if lyrics:
                log(f"letra sincronizada: {len(lyrics)} líneas")
            else:
                log("sin letra sincronizada (sin carteles)")

        if lyrics and t["status"] == "Playing":
            i = current_line_index(lyrics, t["pos"] + OFFSET)
            if i != idx:
                idx = i
                if i >= 0 and lyrics[i][1]:
                    show(lyrics[i][1], t["title"])

        time.sleep(POLL)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
