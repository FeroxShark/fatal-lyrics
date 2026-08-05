"""Menu interactivo de config (fatal config)."""
import os
import signal

from . import config
from . import ipc
from . import system

def _pick(title, options, current):
    """Numbered menu; enter = keep the current value. options: [(label, value)]."""
    print(f"\n{title}   (now: {_fmt(current)})")
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


def _ask_screens(current):
    """Pantallas: auto / todas / una / varias. Devuelve str o lista."""
    mons = system._monitors()
    opts = [("auto (first monitor)", "auto"), ("all screens", "all")]
    opts += [(f"only {n}  ({info})", n) for n, info in mons]
    if len(mons) > 1:
        opts.append(("several (pick which)", "__multi__"))
    v = _pick("Which screen(s) should dialogs appear on?", opts, _fmt(current))
    if v != "__multi__":
        return v
    for i, (n, info) in enumerate(mons, 1):
        print(f"  {i}) {n}  ({info})")
    raw = input("comma-separated numbers (e.g. 1,3) > ").strip()
    picked = [mons[int(t) - 1][0] for t in (t.strip() for t in raw.split(","))
              if t.isdigit() and 1 <= int(t) <= len(mons)]
    return picked or None


def _ask_player(current):
    players = system._players()
    if not players:
        return _ask_text("MPRIS player to follow (see: playerctl -l)", current)
    v = _pick("MPRIS player to follow",
              [(p, p) for p in players] + [("other (type it in)", "__manual__")], current)
    if v == "__manual__":
        return _ask_text("Player name (see: playerctl -l)", current)
    return v


def _ask_crt_order(current):
    """Orden de las pantallas del tubo, de izquierda a derecha.

    Es lo que decide dónde cae cada pedazo de una línea partida: la primera de
    la lista se queda con el principio. Anda con la cantidad de monitores que
    haya — con uno solo no cambia nada."""
    mons = system._monitors_lr()
    if len(mons) < 2:
        # cero = no hay lista de monitores (fuera de Hyprland no se puede pedir)
        print("\n  no screen list available (Hyprland only), nothing to order"
              if not mons else
              "\n  only one screen detected, the order changes nothing")
        input("  enter to go back ")
        return None
    print(f"\nScreen order, left to right   (now: {_fmt(current)})")
    print("  it decides where each piece of a split line lands\n")
    for i, (name, info) in enumerate(mons, 1):
        print(f"  {i}) {name}  ({info})")
    print("\n  type the numbers left to right (e.g. 2,1,3),")
    print("  'a' to follow how they are physically placed, enter to keep it")
    raw = input("> ").strip().lower()
    if not raw:
        return None
    if raw in ("a", "auto"):
        return "auto"
    picked = [t.strip() for t in raw.replace(" ", ",").split(",") if t.strip()]
    if not all(t.isdigit() and 1 <= int(t) <= len(mons) for t in picked):
        print("  numbers from the list, separated by commas")
        input("  enter to go back ")
        return None
    names = [mons[int(t) - 1][0] for t in picked]
    if len(set(names)) != len(names):
        print("  a screen twice in the same order")
        input("  enter to go back ")
        return None
    # las que no nombró van al final solas: nadie se queda sin tubo
    return names

YESNO = [("yes", True), ("no", False)]

# (clave, sección, etiqueta, editor). El editor recibe el valor actual y
# devuelve el nuevo, o None para dejarlo como está.
SETTINGS = [
    ("— screen —", None, None, None),
    ("screen", "display", "Screens", _ask_screens),
    ("spawn_area", "display", "Spawn zone", lambda c: _pick("Spawn zone", [
        ("full screen", "full"), ("top", "top"), ("bottom", "bottom"),
        ("left", "left"), ("right", "right"),
        ("edges (leaves the center clear)", "edges")], c)),
    ("scale", "display", "Dialog scale", lambda c: _ask_num("Dialog scale", c, 0.5, 3.0)),
    ("current_scale", "display", "Extra scale, current line",
     lambda c: _ask_num("Extra scale for the current-line dialog", c, 0.5, 3.0)),
    ("max_dialogs", "display", "Max live dialogs (0 = unlimited)",
     lambda c: _ask_int("Max live dialogs at once (0 = unlimited)", c, 0, 50)),
    ("karaoke", "display", "Karaoke (paints word by word)",
     lambda c: _pick("Karaoke (current line paints word by word)", YESNO, c)),

    ("— effects —", None, None, None),
    ("glitch", "effects", "Glitch intensity", lambda c: _pick("Glitch intensity", [
        ("off (clean dialogs)", "off"), ("soft", "soft"),
        ("normal", "normal"), ("aggressive (dying GPU)", "aggressive")], c)),
    ("effects_on_current", "effects", "Current dialog also glitches",
     lambda c: _pick("The current dialog also vibrates/glitches", YESNO, c)),
    ("tearing", "effects", "Split window on old dialogs",
     lambda c: _pick("Split window on old dialogs", YESNO, c)),
    ("burn_in", "effects", "Burn-in shadow when one dies",
     lambda c: _pick("Fading burnt shadow when a dialog dies (burn-in)", YESNO, c)),
    ("cascade", "effects", "Chain death on track change",
     lambda c: _pick("Dialogs die in a chain on track change", YESNO, c)),
    ("death_age_min", "effects", "A dialog dies after at least",
     lambda c: _ask_int("A dialog dies between... (new dialogs after it appears)", c, 1, 50)),
    ("death_age_max", "effects", "...and at most",
     lambda c: _ask_int("...and at most (new dialogs)", c, 1, 50)),
    ("max_lifetime", "effects", "Max lifetime, seconds (0 = unlimited)",
     lambda c: _ask_int("Max lifetime per dialog in seconds (0 = unlimited)", c, 0, 600)),

    ("— vinyl sleeve —", None, None, None),
    ("now_playing", "behavior", "Sleeve with album art",
     lambda c: _pick("Vinyl sleeve (album art on track change)", YESNO, c)),
    ("np_corner", "behavior", "Where it docks", lambda c: _pick("Where should the sleeve dock?", [
        ("top-left", "top-left"), ("top-right", "top-right"),
        ("bottom-left", "bottom-left"), ("bottom-right", "bottom-right"),
        ("always centered (shrinks in place)", "center")], c)),
    ("np_margin", "behavior", "Margin against the edges (px)",
     lambda c: _ask_int("Sleeve margin against the edges (px)", c, 0, 200)),
    ("np_vinyl", "behavior", "Spinning vinyl record",
     lambda c: _pick("Spinning vinyl record peeking out of the sleeve", YESNO, c)),

    ("— CRT mode (fatal crt on/off) —", None, None, None),
    ("enabled", "crt", "Start with the tube on",
     lambda c: _pick("Start with CRT mode on (it covers every screen)", YESNO, c)),
    ("screens", "crt", "Screens the tube takes", _ask_screens),
    ("order", "crt", "Screen order, left to right", _ask_crt_order),
    ("palette", "crt", "Phosphor colour", lambda c: _pick("Phosphor colour", [
        ("auto (one per screen, rotates per track)", "auto"), ("amber", "amber"),
        ("cyan", "cyan"), ("green", "green"), ("violet", "violet"),
        ("red (always critical)", "red")], c)),
    ("split", "crt", "Line across screens", lambda c: _pick(
        "How the line is spread over several screens", [
            ("mixed (whole phrase, short lines cut in pieces)", "mixed"),
            ("whole (never cut)", "whole"),
            ("fragment (always cut short lines)", "fragment")], c)),
    ("director", "crt", "Lyric travels across screens",
     lambda c: _pick("The lyric travels across the screens (director)", YESNO, c)),
    ("focus", "crt", "Focus", lambda c: _pick("Where the lyric goes", [
        ("roam: one screen at a time, the focus moves", "roam"),
        ("all: every screen shows the whole line", "all")], c)),
    ("audio", "crt", "React to the music",
     lambda c: _pick("React to what's actually playing", YESNO, c)),
    ("color_from_pitch", "crt", "Colour follows the register",
     lambda c: _pick("The phosphor leans on the register of what's playing", YESNO, c)),
    ("color_hold", "crt", "Seconds before the colour may change",
     lambda c: _ask_int("Seconds a colour has to stay before it may change", c, 0, 600)),
    ("motifs", "crt", "Animations on the quiet screens",
     lambda c: _pick("Animations on the screens without lyric", YESNO, c)),
    ("water", "crt", "Water animations (sea, shivering pond)",
     lambda c: _pick("The two water animations: a sea in perspective, and a dish "
                     "of water shivering at the frequency of the song", YESNO, c)),
    ("water_amp", "crt", "How much the water moves",
     lambda c: _ask_num("How much the water moves (0 = a flat field of points)",
                        c, 0.0, 1.0)),
    ("quality", "crt", "Render resolution (less = cheaper)",
     lambda c: _ask_num("Resolution the tube is drawn at (1.0 = native)", c, 0.4, 1.0)),
    ("camera", "crt", "Framing movement",
     lambda c: _ask_num("How much the framing moves (0 = still)", c, 0.0, 2.0)),
    ("exit_on", "crt", "How you get out", lambda c: _pick(
        "How you get out of the tube", [
            ("mouse: cursor hidden, click or wheel returns", "mouse"),
            ("keyboard: any key returns, cursor stays visible", "keyboard")], c)),
    ("chrome", "crt", "Console readouts (REC, timecode)",
     lambda c: _pick("Console readouts on the tube", YESNO, c)),
    ("word_flash", "crt", "Jolt as each word lands (0 = none)",
     lambda c: _ask_num("How much each word jolts as it lands: flash, colour "
                        "ghosts and size kick (0 = it simply appears)", c, 0.0, 1.0)),
    ("flicker", "crt", "Beating on the peaks (0 = none)",
     lambda c: _ask_num("How hard the picture beats on the peaks of the song "
                        "(0 = nothing moves with the volume)", c, 0.0, 1.0)),
    ("intensity", "crt", "How restless it is (0 = still)",
     lambda c: _ask_num("How restless the tube is: breaks, static, channel split, "
                        "beat shakes (0 = dead still, 1 = wild)", c, 0.0, 2.0)),
    ("curvature", "crt", "Tube glass curvature",
     lambda c: _ask_num("Tube glass curvature (0 = flat panel)", c, 0.0, 3.0)),
    ("scanlines", "crt", "Scanline depth",
     lambda c: _ask_num("Scanline depth", c, 0.0, 1.0)),
    ("bloom", "crt", "Phosphor glow",
     lambda c: _ask_num("Phosphor glow around the letters", c, 0.0, 3.0)),

    ("— behavior —", None, None, None),
    ("player", "behavior", "Player to follow", _ask_player),
    ("offset", "behavior", "Sync lead time (s)",
     lambda c: _ask_num("Lyric sync lead time in seconds (can be negative)", c, -2.0, 2.0)),
    ("troll_no", "behavior", '"No" button duplicates the dialog',
     lambda c: _pick('The "No" button duplicates the dialog', YESNO, c)),
    ("click_through", "behavior", "Ghost dialogs (clicks pass through)",
     lambda c: _pick("Ghost dialogs (clicks pass through)", YESNO, c)),
    ("pause_clear", "behavior", "Clear after N s paused (0 = never)",
     lambda c: _ask_int("Seconds paused before clearing everything (0 = never)", c, 0, 300)),
    ("game_pause", "behavior", "Auto-pause on fullscreen games",
     lambda c: _pick("Auto-pause when a game is in fullscreen", YESNO, c)),
]

DIM, BOLD, YEL, OFF = "\033[2m", "\033[1m", "\033[33m", "\033[0m"


def _fmt(v):
    if isinstance(v, bool):
        return "yes" if v else "no"
    if isinstance(v, list):
        return ", ".join(str(x) for x in v)
    return str(v)

def _demo():
    """Le pide al daemon un par de carteles de mentira, para ver los cambios
    sin depender de que haya música sonando."""
    pid = system._daemon_pid()
    if not pid or not os.path.exists(ipc.SOCK_PATH):
        print("  fatal-lyrics isn't running — start it with: fatal on")
        return
    os.kill(pid, signal.SIGUSR1)
    print("  demo dialogs sent")

def _menu(cfg, opening):
    print("\033[H\033[J", end="")
    print(f"{BOLD}fatal-lyrics — config{OFF}   "
          f"{DIM}every change applies live, no restart{OFF}\n")
    rows = {}
    n = 0
    for key, section, label, editor in SETTINGS:
        if section is None:
            print(f"\n {DIM}{key}{OFF}")
            continue
        n += 1
        rows[n] = (key, section, label, editor)
        cur, was = cfg[section][key], opening[section][key]
        dots = "." * max(1, 34 - len(label))
        mark = f" {YEL}*{OFF} {DIM}(was {_fmt(was)}){OFF}" if cur != was else ""
        print(f"  {n:>2}  {label} {DIM}{dots}{OFF} {_fmt(cur)}{mark}")
    print(f"\n {DIM}number{OFF} edit   {DIM}d{OFF} demo dialogs   "
          f"{DIM}u{OFF} undo everything   {DIM}q{OFF} done")
    return rows


def setup():
    """Menú: todo a la vista, se edita sólo lo que se quiere, se aplica al toque."""
    cfg = config.load_config()
    opening = {s: dict(v) for s, v in cfg.items()}
    msg = ""
    while True:
        rows = _menu(cfg, opening)
        if msg:
            print(f"\n{msg}")
            msg = ""
        raw = input("\n> ").strip().lower()

        if raw in ("q", "quit", "exit", "x", ""):
            changed = [(k, s) for s, vals in cfg.items() for k in vals
                       if vals[k] != opening[s][k]]
            print("\033[H\033[J", end="")
            if changed:
                print(f"Saved to {config.CONFIG_PATH}:")
                for key, sec in changed:
                    print(f"  {sec}.{key} = {config._toml_val(cfg[sec][key])}")
            else:
                print("No changes.")
            return

        if raw in ("d", "demo"):
            _demo()
            input("  enter to go back ")
            continue

        if raw in ("u", "undo"):
            back = {k: (s, opening[s][k]) for s, vals in cfg.items() for k in vals
                    if vals[k] != opening[s][k]}
            if not back:
                msg = "  nothing to undo"
                continue
            config._save_config(back)
            for key, (sec, val) in back.items():
                cfg[sec][key] = val
            msg = f"  {len(back)} setting(s) back to how you found them"
            continue

        if not (raw.isdigit() and int(raw) in rows):
            msg = "  pick a number from the list, or q to finish"
            continue

        key, section, _, editor = rows[int(raw)]
        print("\033[H\033[J", end="")
        try:
            new = editor(cfg[section][key])
        except (KeyboardInterrupt, EOFError):
            continue
        if new is None or new == cfg[section][key]:
            continue
        cfg[section][key] = new
        config._save_config({key: (section, new)})
        msg = f"  {section}.{key} = {config._toml_val(new)}"
        if key in ("death_age_min", "death_age_max") and \
                cfg["effects"]["death_age_min"] > cfg["effects"]["death_age_max"]:
            msg += f"\n  {YEL}heads up:{OFF} the minimum is above the maximum"
