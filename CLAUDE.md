# cartelitos / fatal-lyrics

## Qué es y para qué

Las letras sincronizadas de lo que suena en Spotify, tiradas en pantalla como **diálogos de error
de Win95**. Tiene un segundo modo, el **CRT**, donde cada monitor se vuelve un tubo de rayos
catódicos con la letra adentro.

Repo **público**: `https://github.com/FeroxShark/fatal-lyrics`. El binario de sistema es
`~/.local/bin/fatal` (symlink a `bin/fatal`; `install.sh` lo pone junto con el `.desktop` y el
ícono). El launcher es relocatable, con `qs -p`.

Sistema (2026-10): CachyOS + **Hyprland 0.56 con config en Lua** — `hyprctl keyword` ya no hace
nada (contesta "Use eval" con código 0): todo va por `hyprctl eval`. Monitores: `DP-2` izq,
vertical (x=0) · `HDMI-A-1` principal (x=1080, ahí van los carteles) · `DP-1` der (x=3000, panel
de widgets en ws31: el CRT no lo toma). Los DP-4/DP-5/DP-6/HDMI-A-2 de `docs/` son del setup viejo.

## Reglas duras

- **Dos procesos, no uno**: daemon Python + overlay Quickshell, por socket Unix. Diagnóstico mira
  **los dos PIDs** (`fatal status`: ON / HALF / OFF). Detalle: `docs/CONCEPTOS.md`.
- **Config = TOML con hot-reload** (`~/.config/cartelitos/config.toml`). Nada necesita
  `fatal restart`. **Todas las opciones viven en la ventana de Ajustes** (`fatal ajustes`;
  `fatal config` es alias): nada de menús de terminal. Perilla nueva = fila en `settings.GROUPS`.
- **REGLA: una animación por pantalla.** Textual de Ferox: "no quiero que ninguna animación se
  superponga con ninguna". En cada pantalla hay UNA cosa a la vez — o el motivo, o el aro, o la
  letra con su entrada, o el instrumental. Por eso el aro apaga el motivo de su pantalla (`dim` a
  0 en 220 ms) en vez de contar encima de él. Excepciones: el rayo del salto (va por el BORDE de
  la pantalla del medio) y el GOLPE del bajo (Ferox 2026-10-19): cada bombo pulsa cámara, tubo y
  tamaño del motivo de TODA la pared, más un destello chico de agudos; vuelve a 1 solo.
- **REGLA: hay UN lenguaje de movimiento, y vive en `shell/Motion.qml`.** Todo lo que entra
  entra igual — snap `OutExpo` con asentamiento visible (`enterMs`, 320 ms; `enterFastMs` para
  lo que entra encima de algo que ya está pasando) —, todo lo que se va se va rápido (`exitMs`,
  140, `InQuad`), la cámara se mueve una vez y se queda quieta (`cameraMs`; salvo el golpe,
  `kickCam`), y el glitch es un
  PUENTE de dos o tres cuadros entre escena y escena (`bridgeMs`), nunca un efecto que dura. Un
  `Behavior` con otra duración tiene que justificarla. Sale del video de Ferox
  (`docs/plans/2026-09-04-fluidez-referencia.md`): lo fluido no son más cuadros: es una sola
  gramática, holds largos y una deriva uniforme por debajo que nunca para.
- **REGLA: los eventos tienen PRESUPUESTO, y es la perilla `pace`** (`calm | normal | wild`,
  default `normal`, tabla `crtPaceTable` en `shell.qml`). No es una velocidad: nada se mueve más
  despacio. Es cuántas cosas tienen permiso de pasar por minuto — cuánto dura el dibujo de una
  pantalla antes de poder cambiar (12 s), cada cuánto la pared puede cambiar de canal (20 s),
  cada cuánto una pantalla puede romperse (4 s), y qué tan grande es el latido de la cámara y
  del motivo. `wild` devuelve los números de la tanda 3 (salvo las columnas `kick*`, nuevas). El
  golpe escala por CARÁCTER del tema (`crtCharacter`: `char` del daemon, o BPM + energía del
  mood): tema lento = pulso chico y lento, agitado = grande y seco. Un número de amplitud o de
  frecuencia nuevo va a la TABLA: repartido en ternarios, `wild` deja de ser verificable.
- **Casi todo lo raro tiene una razón medida.** Los gotchas caros están documentados EN EL CÓDIGO.
  Leerlos antes de "optimizar" algo que parece raro.

## Cómo correrlo / testearlo

```bash
fatal on | off | restart | status
fatal demo                 # SIGUSR1: carteles falsos, sin música
fatal ajustes              # ventana Win95 con todas las opciones (la bandeja es corta)
fatal crt toggle           # también Super+Shift+Y
fatal sync + | -           # ajuste fino ±0.1s, también Super+Alt+Right/Left o la ventana de Ajustes
python3 -m unittest discover -s tests
```

### Para VER un motif

```bash
fatal crt motif dunes --screen DP-2    # esa pantalla, ese dibujo, ya
fatal crt motif tunnel --screen all    # toda la pared (rompe la unicidad a propósito)
fatal crt motif off                    # vuelve el sorteo normal
docs/plans/motif-force.py dunes DP-2 10 --shot t4-dunes   # + captura, y deja todo como estaba
```

**NUNCA pescar un motif con palabras clave ni rerollear con `cue drop`** (`drive-motif.py` y
`motif-hunt.py` son OBSOLETOS: esperaban minutos al sorteo). El forzado pisa pool, hold, filtro y
palabra clave, y se ve sin música. Kinds válidos: `fatal crt motif --help`. `splitflap` y `testcard`
(pantallas planas) ya no entran al sorteo; sólo se ven forzados.

Hyprland: binds y `no_anim` de las capas viven en `packaging/hyprland.lua` (`dofile` desde
`~/.config/hypr/hyprland.lua`). Autostart: **UNO solo**, la unit de usuario
`packaging/fatal-lyrics.service` (`fatal run`); `fatal on|off|restart` pasan por `systemctl --user`.
No reintroducir un segundo (`docs/TRAMPAS.md`).

## Dónde está el resto (leer sólo lo que toca)

**Tope de este archivo: ~7.000 caracteres.** Reglas duras + cómo correr + índice. Lo demás va a `docs/`.

- `docs/CONCEPTOS.md` — Cómo pensarlo: dos procesos, config con hot-reload, interruptor del CRT, línea siguiente, salto, motivos, entradas, sync, foco y idioma de la letra.
- `docs/MAPA.md` — Mapa del código: qué hace cada archivo, propiedad y perilla, y dónde están los cachés.
- `docs/TRAMPAS.md` — Bugs que ya pasaron y por qué. Antes de diagnosticar algo raro, buscá acá. Cada trampa nueva va acá.
- `docs/NUMEROS-MEDIDOS.md` — Mediciones de CPU/latencia y cómo se tomaron. Los números nuevos van acá.
- `docs/PENDIENTES.md` — Backlog vivo. Leerlo al planear una tanda.
- `docs/tanda8-estado/` — estado de la tanda 8 por frente.
- `docs/plans/` — planes y feedback por tanda (gitignored: repo público).

## Glosario

- **cartelito** — un diálogo de error con una línea de la letra.
- **funda** — la ventana con la portada del disco (bevel Win95, disco que asoma y gira).
- **burn-in** — la silueta quemada que queda cuando un cartel muere.
- **cascade** — muerte en cadena de los carteles al cambiar de tema.
- **karaoke** — pintar la línea actual palabra por palabra.
- **motif** — la animación que va en las pantallas que no tienen letra.

## Decisiones cerradas (Ferox las descartó, no re-proponer)

- Sonidos, easter egg `wolf.exe` (el video de Mr Wolf es UN tema puntual, no insistir).
- BSOD como MODO permanente: descartado. 2026-09-15: aprobado como evento RARO (`crt.rare`,
  corrida 7) — no reabrir la idea de un modo aparte, ya existe como raro.
- Temas visuales (win95 / XP / vaporwave): le gustó la idea pero **no la pidió**. Esperar a que la
  pida.
- Defaults que él usa: `karaoke = true`, `max_dialogs = 0` (sin límite), `cascade` y `np_vinyl` en
  true.
