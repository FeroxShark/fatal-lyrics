"""Icono de la bandeja (GTK + AyatanaAppIndicator3, opcional)."""
import os
import shutil
import subprocess
import threading

from . import config
from .util import log

# lo único que se cambia desde la bandeja, de un click y con el estado en el
# texto. Todo lo demás vive en la ventana de Ajustes (`fatal ajustes`): con los
# ocho submenús de antes el menú pasaba las veinte filas.
TRAY_TOGGLES = [
    ("karaoke", "display", "Karaoke"),
]


def start_tray():
    """Ícono en la bandeja del sistema mientras el daemon está vivo (StatusNotifierItem
    vía AyatanaAppIndicator3). Opcional: si gtk3/libayatana-appindicator no están
    instalados, el daemon sigue andando igual, sin bandeja.

    El menú es corto a propósito: abrir Ajustes, prender el tubo, el karaoke y
    salir. El estado va en el TEXTO de cada ítem ("Karaoke: on"), no en
    checkboxes: DBusMenu los expone, pero varios shells (caelestia, entre otros)
    dibujan sólo ícono + texto y el tilde no se ve."""
    try:
        import gi
        gi.require_version("Gtk", "3.0")
        gi.require_version("AyatanaAppIndicator3", "0.1")
        from gi.repository import Gtk, GLib, AyatanaAppIndicator3
    except Exception as e:
        log(f"tray not available ({e}), continuing without an icon")
        return

    fatal_bin = shutil.which("fatal") or os.path.expanduser("~/.local/bin/fatal")
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

        # la ventana es otro proceso (Quickshell); `fatal ajustes` no abre una
        # segunda si ya hay una
        item(menu, "Settings…", on_click=lambda: subprocess.Popen([fatal_bin, "ajustes"]))
        menu.append(Gtk.SeparatorMenuItem())

        # el tubo se prende/apaga en vivo (no toca el archivo: `enabled` es sólo
        # con qué estado arranca), así que la etiqueta lee el interruptor real
        def toggle_crt():
            config.set_crt(not config.crt_on())
            GLib.idle_add(refresh)

        item(menu, "CRT mode", on_click=toggle_crt,
             dynamic=lambda: f"CRT mode: {'on' if config.crt_on() else 'off'}")

        for key, section, title in TRAY_TOGGLES:
            item(menu, title,
                 on_click=lambda k=key, s=section: config.set_option(k, s, not config.CFG[s][k]),
                 dynamic=lambda t=title, k=key, s=section:
                     f"{t}: {'on' if config.CFG[s][k] else 'off'}")

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
