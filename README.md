# fatal-lyrics

Letras de Spotify sincronizadas, mostradas como diálogos de error de Windows 95
que van apareciendo en tu escritorio. Inspirado en el video de
[*Me and Mr Wolf* — The Real Tuesday Weld](https://www.youtube.com/watch?v=e1_BBW1umyE).

- Cada línea de la letra aparece como un cartel de error en una posición random.
- El cartel de la línea que suena **ahora** es más grande y está quieto.
- Los carteles viejos vibran como hologramas cyberpunk, se glitchean con
  artefactos tipo GPU rota (bloques magenta/verde/morado) y mueren con un
  colapso estilo CRT.
- Al cambiar de canción aparece un cartel *Now Playing* con la portada del álbum.
- Íconos de Windows random: error, advertencia, pregunta, info.
- Los carteles se pueden **arrastrar** desde la barra de título.
- `Yes` / `Cancel` / `✕` cierran el cartel. `No` lo **duplica** (como los popups
  de malware de los 2000).
- Si detecta un juego corriendo (CS2 por defecto) se pausa solo.

## Requisitos

- Wayland con un compositor wlroots-like (probado en **Hyprland**)
- [Quickshell](https://quickshell.org/) (`qs`)
- `playerctl`
- `python3` (solo stdlib)
- Spotify (o cualquier player MPRIS que se anuncie como `spotify`)

Las letras salen de [lrclib.net](https://lrclib.net) (gratis, sin API key).

## Instalación

```bash
git clone https://github.com/FeroxShark/fatal-lyrics ~/cartelitos
~/cartelitos/install.sh
```

Después:

```bash
cartelitos          # toggle on/off
cartelitos status   # ON / OFF
```

## Configuración

En `shell/shell.qml`:

| Propiedad      | Qué hace                                      | Default  |
|----------------|-----------------------------------------------|----------|
| `targetScreen` | Monitor donde aparecen los carteles           | `"DP-6"` |
| `maxDialogs`   | Máximo de carteles vivos a la vez             | `12`     |

En `cartelitos.py`:

| Constante    | Qué hace                                        | Default   |
|--------------|-------------------------------------------------|-----------|
| `GAME_PROCS` | Procesos que pausan los carteles automáticamente | `("cs2",)`|
| `POLL`       | Intervalo de sondeo de posición (segundos)       | `0.3`     |
| `OFFSET`     | Adelanto de sync (segundos)                      | `0.15`    |

Cambiá `targetScreen` por el nombre de tu monitor (`hyprctl monitors` para verlo).

## Cómo funciona

```
Spotify ──playerctl (MPRIS)──▶ cartelitos.py ──socket Unix──▶ Quickshell overlay
                                    │
                                    └──HTTP──▶ lrclib.net (letra sincronizada LRC)
```

El daemon sondea la posición de reproducción, resuelve qué línea corresponde y
le manda eventos JSON al overlay por `$XDG_RUNTIME_DIR/cartelitos.sock`.

## Desinstalar

```bash
cartelitos off
rm ~/.local/bin/cartelitos ~/.config/quickshell/cartelitos
rm -rf ~/cartelitos
```

## Licencia

MIT
