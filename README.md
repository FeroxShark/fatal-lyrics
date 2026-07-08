# fatal-lyrics

Letras de Spotify sincronizadas, mostradas como diálogos de error de Windows 95
que van apareciendo en tu escritorio. Inspirado en el video de
[*Me and Mr Wolf* — The Real Tuesday Weld](https://www.youtube.com/watch?v=e1_BBW1umyE).

- Cada línea de la letra aparece como un cartel de error en una posición random.
- El cartel de la línea que suena **ahora** es más grande y está quieto.
- Los carteles viejos vibran como hologramas, se glitchean con artefactos tipo
  GPU rota (bloques magenta/verde/morado), quedan con la **ventana partida**
  (tearing real) y mueren con un colapso estilo CRT.
- Al cambiar de canción aparece una **funda de vinilo**: caja cuadrada con la
  portada del álbum y borde estilo Windows clásico. Sale grande en el centro y
  a los segundos se estaciona chiquita en una esquina (configurable, o siempre
  centrada), con una **barra de progreso Win95** que avanza con la canción.
  Se puede arrastrar a donde quieras; click seco = esconderla hasta el próximo tema.
- De la funda asoma un **disco de vinilo girando**, con la portada de etiqueta.
- Al cambiar de canción los carteles viejos no se esfuman: mueren **en cadena**,
  un dominó de colapsos CRT del más viejo al más nuevo.
- Modo **karaoke** opcional: la línea actual se va pintando palabra por palabra
  a medida que se canta (timing estimado — lrclib da tiempos por línea).
- **Multi-monitor**: `screen = "all"` (o una lista) muestra los carteles en
  varias pantallas a la vez, cada monitor con sus propias posiciones random.
- Los carteles muertos dejan una **sombra quemada** (burn-in CRT) que se
  desvanece en un par de segundos.
- Íconos de Windows random: error, advertencia, pregunta, info.
- Los carteles se pueden **arrastrar** desde la barra de título.
- En el cartel actual: `Yes` / `Cancel` / `✕` cierran, `No` lo **duplica** (como
  los popups de malware de los 2000). En los viejos (rotos): click = cerrar.
- Si detecta un juego corriendo se pausa solo; si pausás la música mucho tiempo,
  limpia todo; cada cartel tiene vida máxima (nada queda flotando para siempre).

## Requisitos

- Wayland con un compositor wlroots-like (probado en **Hyprland**)
- [Quickshell](https://quickshell.org/) (`qs`)
- `playerctl`
- `python3` ≥ 3.11 (solo stdlib)
- Spotify (o cualquier player MPRIS — configurable)

Las letras salen de [lrclib.net](https://lrclib.net) (gratis, sin API key).

## Instalación

### Arch Linux (AUR)

```bash
yay -S fatal-lyrics-git
```

### Manual

```bash
git clone https://github.com/FeroxShark/fatal-lyrics ~/fatal-lyrics
~/fatal-lyrics/install.sh
```

## Uso

```bash
cartelitos            # toggle on/off
cartelitos on|off     # explícito
cartelitos restart    # reiniciar (aplica cambios de config)
cartelitos status     # ON / OFF
cartelitos setup      # menú interactivo de configuración (recomendado)
cartelitos config     # abre la config en $EDITOR
```

## Configuración

La primera vez se crea `~/.config/cartelitos/config.toml` con defaults.
Lo más fácil es `cartelitos setup` (menú interactivo que detecta tus monitores
y reinicia solo). También podés editarla a mano (`cartelitos config`) y aplicar
con `cartelitos restart`.

| Sección    | Opción               | Qué hace                                                       | Default     |
|------------|----------------------|----------------------------------------------------------------|-------------|
| `display`  | `screen`             | `"auto"` (primero), `"all"` (todos), nombre (`"DP-1"`) o lista (`["DP-1", "DP-2"]`) | `"auto"`   |
| `display`  | `max_dialogs`        | Máximo de carteles vivos a la vez (`0` = sin límite)           | `0`         |
| `display`  | `scale`              | Tamaño base de todos los carteles                              | `1.0`       |
| `display`  | `current_scale`      | Factor extra del cartel de la línea actual                     | `1.3`       |
| `display`  | `spawn_area`         | Zona de aparición: `full`/`top`/`bottom`/`left`/`right`/`edges` | `"full"`   |
| `display`  | `karaoke`            | La línea actual se pinta palabra por palabra                   | `false`     |
| `effects`  | `glitch`             | Intensidad: `off`/`soft`/`normal`/`aggressive`                 | `"normal"`  |
| `effects`  | `effects_on_current` | El cartel actual también vibra/glitchea                        | `false`     |
| `effects`  | `tearing`            | Los viejos quedan con la ventana partida                       | `true`      |
| `effects`  | `death_age_min/max`  | Un cartel muere entre N y M carteles después                   | `3` / `7`   |
| `effects`  | `max_lifetime`       | Vida máxima por cartel en segundos (`0` = sin límite)          | `60`        |
| `effects`  | `burn_in`            | Los carteles muertos dejan una sombra quemada que se desvanece | `true`      |
| `effects`  | `cascade`            | Al cambiar de canción los carteles mueren en cadena (dominó)   | `true`      |
| `behavior` | `now_playing`        | Funda de vinilo con la portada al cambiar de canción           | `true`      |
| `behavior` | `np_corner`          | Dónde se estaciona: `top-left`/`top-right`/`bottom-left`/`bottom-right`/`center` | `"top-right"` |
| `behavior` | `np_margin`          | Píxeles libres contra los bordes (por si hay una barra/panel)  | `14`        |
| `behavior` | `np_vinyl`           | Disco de vinilo que asoma girando de la funda                  | `true`      |
| `behavior` | `troll_no`           | El botón `No` duplica el cartel                                | `true`      |
| `behavior` | `click_through`      | Los carteles no capturan el mouse                              | `false`     |
| `behavior` | `pause_clear`        | Segundos en pausa antes de limpiar todo (`0` = nunca)          | `15`        |
| `behavior` | `player`             | Nombre del player MPRIS (`playerctl -l`)                       | `"spotify"` |
| `behavior` | `offset`             | Adelanto de sincronización en segundos                         | `0.15`      |
| `behavior` | `game_procs`         | Procesos que pausan los carteles automáticamente               | `["cs2"]`   |

## Cómo funciona

```
Spotify ──playerctl (MPRIS)──▶ cartelitos.py ──socket Unix──▶ Quickshell overlay
                                    │
                                    └──HTTP──▶ lrclib.net (letra sincronizada LRC)
```

El daemon sondea la posición de reproducción, resuelve qué línea corresponde y
le manda eventos JSON al overlay por `$XDG_RUNTIME_DIR/cartelitos.sock`.
La config viaja por el mismo socket al conectar.

## Desinstalar

```bash
cartelitos off
# AUR: sudo pacman -R fatal-lyrics-git
# manual:
rm ~/.local/bin/cartelitos && rm -rf ~/fatal-lyrics
rm -rf ~/.config/cartelitos   # opcional: borrar config
```

## Licencia

MIT
