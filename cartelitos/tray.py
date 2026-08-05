"""Icono de la bandeja (GTK + AyatanaAppIndicator3, opcional)."""
import os
import shutil
import subprocess
import threading

from . import config
from . import ipc
from . import system
from .util import log

# submenús de la bandeja: (clave, sección, título, [(etiqueta, valor)])
TRAY_CHOICES = [
    ("glitch", "effects", "Glitch", [
        ("Off", "off"), ("Soft", "soft"), ("Normal", "normal"),
        ("Aggressive", "aggressive")]),
    ("spawn_area", "display", "Spawn zone", [
        ("Full screen", "full"), ("Top", "top"), ("Bottom", "bottom"),
        ("Left", "left"), ("Right", "right"), ("Edges", "edges")]),
    ("palette", "crt", "CRT colours", [
        ("Album cover", "album"), ("Auto (by register)", "auto"),
        ("Dragons", "dragons"), ("Ado", "ado"), ("Poison", "poison"),
        ("Bloodline", "bloodline"), ("Vapor", "vapor"), ("Bone", "bone")]),
    ("split", "crt", "CRT split", [
        ("Mixed", "mixed"), ("Never cut", "whole"), ("Always cut", "fragment")]),
    ("exit_on", "crt", "CRT exit", [
        ("Mouse (cursor hidden)", "mouse"), ("Keyboard (any key)", "keyboard")]),
    ("flicker", "crt", "CRT beating (peaks only)", [
        ("Off", 0.0), ("Gentle", 0.15), ("Normal", 0.25), ("Hard", 0.7)]),
    ("word_flash", "crt", "CRT word flash", [
        ("Off", 0.0), ("Gentle", 0.15), ("Normal", 0.3), ("Hard", 0.8)]),
    ("water_amp", "crt", "CRT water", [
        ("Flat", 0.0), ("Calm", 0.3), ("Normal", 0.55), ("Rough", 0.9)]),
]
# toggles que se cambian de un click, con el estado en el texto
TRAY_TOGGLES = [
    ("karaoke", "display", "Karaoke"),
    ("now_playing", "behavior", "Album art"),
    ("tearing", "effects", "Tearing"),
]
SCALE_STEP = 0.1


def start_tray():
    """Ícono en la bandeja del sistema mientras el daemon está vivo (StatusNotifierItem
    vía AyatanaAppIndicator3). Opcional: si gtk3/libayatana-appindicator no están
    instalados, el daemon sigue andando igual, sin bandeja.

    El estado va en el TEXTO de cada ítem ("Glitch: normal", "• Soft"), no en
    checkboxes: DBusMenu los expone, pero varios shells (caelestia, entre otros)
    dibujan sólo ícono + texto y el tilde no se ve. Los submenús sí se dibujan."""
    try:
        import gi
        gi.require_version("Gtk", "3.0")
        gi.require_version("AyatanaAppIndicator3", "0.1")
        from gi.repository import Gtk, GLib, AyatanaAppIndicator3
    except Exception as e:
        log(f"tray not available ({e}), continuing without an icon")
        return

    fatal_bin = shutil.which("fatal") or os.path.expanduser("~/.local/bin/fatal")
    term = system._terminal()
    labels = []   # [(item, función que devuelve el texto)] para refrescar

    def item(menu, label, on_click=None, dynamic=None):
        it = Gtk.MenuItem(label=label)
        if on_click:
            it.connect("activate", lambda *_: on_click())
        else:
            it.set_sensitive(False)
        if dynamic:
            labels.append((it, dynamic))
        menu.append(it)
        return it

    def run():
        indicator = AyatanaAppIndicator3.Indicator.new(
            "cartelitos", "dialog-warning",
            AyatanaAppIndicator3.IndicatorCategory.APPLICATION_STATUS)
        indicator.set_status(AyatanaAppIndicator3.IndicatorStatus.ACTIVE)
        indicator.set_title("Fatal Lyrics")

        menu = Gtk.Menu()
        item(menu, "Fatal Lyrics active")
        menu.append(Gtk.SeparatorMenuItem())

        for key, section, title, options in TRAY_CHOICES:
            sub = Gtk.Menu()
            for label, value in options:
                # el punto marca la opción activa: el tilde de DBusMenu no se dibuja
                item(sub, label,
                     on_click=lambda k=key, s=section, v=value: config.set_option(k, s, v),
                     dynamic=lambda l=label, k=key, s=section, v=value:
                         ("• " if config.CFG[s][k] == v else "   ") + l)
            root_item = item(menu, title,
                             dynamic=lambda t=title, k=key, s=section:
                                 f"{t}: {config.CFG[s][k]}")
            root_item.set_sensitive(True)
            root_item.set_submenu(sub)

        size = Gtk.Menu()
        item(size, "Bigger", on_click=lambda: config.set_option(
            "scale", "display",
            round(min(config.CFG["display"]["scale"] + SCALE_STEP, 3.0), 2)))
        item(size, "Smaller", on_click=lambda: config.set_option(
            "scale", "display",
            round(max(config.CFG["display"]["scale"] - SCALE_STEP, 0.5), 2)))
        item(size, "Reset", on_click=lambda: config.set_option("scale", "display", 1.0))
        size_root = item(menu, "Size",
                         dynamic=lambda: f"Size: {config.CFG['display']['scale']}")
        size_root.set_sensitive(True)
        size_root.set_submenu(size)

        for key, section, title in TRAY_TOGGLES:
            item(menu, title,
                 on_click=lambda k=key, s=section: config.set_option(k, s, not config.CFG[s][k]),
                 dynamic=lambda t=title, k=key, s=section:
                     f"{t}: {'on' if config.CFG[s][k] else 'off'}")

        # el tubo se prende/apaga en vivo (no toca el archivo: `enabled` es sólo
        # con qué estado arranca), así que la etiqueta lee el interruptor real
        def toggle_crt():
            config.set_crt(not config.crt_on())
            GLib.idle_add(refresh)

        item(menu, "CRT mode", on_click=toggle_crt,
             dynamic=lambda: f"CRT mode: {'on' if config.crt_on() else 'off'}")

        menu.append(Gtk.SeparatorMenuItem())
        item(menu, "Sliders…", on_click=lambda: subprocess.Popen([fatal_bin, "tune"]))
        item(menu, "Demo dialogs", on_click=lambda: ipc.demo())
        if term:
            item(menu, "All settings…",
                 on_click=lambda: subprocess.Popen([term, "-e", fatal_bin, "config"]))
        menu.append(Gtk.SeparatorMenuItem())
        item(menu, "Quit", on_click=lambda: subprocess.Popen([fatal_bin, "off"]))

        def refresh():
            for it, text in labels:
                it.set_label(text())
            return False   # idle_add: una sola pasada

        refresh()
        menu.show_all()
        indicator.set_menu(menu)
        # el watcher corre en otro hilo; GTK sólo se toca desde el suyo
        config._tray_refresh = lambda: GLib.idle_add(refresh)
        Gtk.main()

    threading.Thread(target=run, daemon=True, name="tray").start()
