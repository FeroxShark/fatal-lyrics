# Motivos de loop para el CRT (integrados el 2026-09-27)

**Ya están en el overlay**: `shell/<Kind>.qml`, `shell/MotifBase.qml`, `shell/Ease.js`,
`shell/Dots.js`, `shell/maze.frag(.qsb)`, registrados en `Motif.qml` y en `motifKinds`/`motifGroups`.
Lo de `shell/` es la fuente: si tocás uno, copialo acá (imports `"../Ease.js"`) para renderizarlo.
Las copias son idénticas salvo los imports.

**Nada de `Canvas`** (2026-09-27): un Canvas se rasteriza en el procesador y costaba 50–110 ms por
cuadro a 1080p (mystify y vector a 110–120 % de CPU en vivo con tres pantallas). Las líneas y
rellenos van por `MShape.qml` (Qt Quick Shapes, GeometryRenderer + capa MSAA 4×): el motivo arma
`styles[]` (grosor, color, relleno — colores de QML con `E.col`, no el texto CSS de `E.css`) y
`geo[]` (polilíneas de `Qt.point` por estilo) en `onFrame`, y cada estilo es UN ShapePath. El
texto va en `Text` (splitflap, el renglón de defrag). Medido en vivo, tres pantallas con el mismo
motivo: túnel 24 %, mystify/harmonograph/splitflap/maze 24–28 %, vector 31 %, pipes 45 %,
swarm/defrag ~65 %. Para medir CPU sin abrir nada en pantalla: una `QQuickView` de Wayland que
NUNCA se muestra + `grabWindow()` (usa la placa de verdad; con `offscreen` sin
`QT_QUICK_BACKEND=rhi` es el backend de software y los Shapes tardan 500 ms). Ojo: ahí el
CurveRenderer deja de dibujar desde la segunda captura; por eso `MShape` usa GeometryRenderer.

Ocho dibujos nuevos para las pantallas del CRT que no tienen letra (lo que hoy hacen
`tunnel`, `plasma`, `dunes`, etc.). Cada uno es un **loop de 15 s exactos**: 8 compases a
128 BPM = 32 tiempos = 900 cuadros, y el cuadro 900 es el cuadro 0. Se renderizan pasando por
el **vidrio real** (`shell/signal.frag.qsb` → `shell/crt.frag.qsb`) con la fila de
`crtTubeTable` y la paleta con que mejor se ven.

```
./render.py <kind>                   # out/<kind>.mp4 — loop con audio, chequea la costura
./render.py <kind> --portrait        # la pantalla vertical (DP-5, 1080×1920)
./render.py <kind> --stills 1,6.2    # cuadros sueltos (medio segundo de precalentamiento)
./render.py <kind> --flat            # sin vidrio: el motivo pelado
./render.py <kind> --tube arcade --scheme vapor
./render.py --all                    # los ocho + costura + verticales + contact.png + all-loops.mp4
./sheet.sh <kind> 1,4,9,13 [args]    # 2×2 de cuadros para revisar a ojo
```

Nunca abre nada en pantalla (plataforma `offscreen` ASIGNADA, ver `docs/TRAMPAS.md`). Un loop
tarda ~2 min.

## La partitura del preview

`Loop.js`: estrofa (compases 1–4), subida con redoble que acelera (5–6), drop (7–8), y vuelve.
`LoopFeed.qml` publica con esa partitura **los mismos nombres que Crt.qml le pasa a `Motif`**
(`level`, `low`, `high`, `energy`, `drop`, `section`, `tick`, `beat`, `kick`, `beatMs`,
`bpmLive`, `surge`, `nextWord`, `lineNo`, `lines`, `waveL/R`), y el reloj del tubo arranca en
3000 s, como en el overlay. El audio del mp4 es sólo para mirar la sincronía: el programa no
tiene sonidos (decisión cerrada).

## Reglas con que están hechos

- **Función pura del reloj.** Nada de `Behavior`/`Animation`/`FrameAnimation`: cada cuadro sale
  de `clock` y de los contadores. Lo que deriva es periódico en 15 s (`lt = clock mod 15`,
  `Ease.pnoise`, rebotes con un número entero de idas y vueltas).
- **El audio mueve amplitud, nunca velocidad.** Es la trampa del hiperespacio y del túnel
  (`clock × velocidad` teletransporta todo con cada cambio de volumen). Lo que avanza a los
  saltos lo hace por `tick`/`kick` con el snap de Motion (OutExpo 320–340 ms) y después se queda
  quieto: el paso del laberinto, el octavo de vuelta del teseracto, la palabra de los cursores.
- **Los relojes capturados** (`tickAt`, `kickAt`, `dropAt`) viven en `motifs/MotifBase.qml`:
  `bp` (cuánto va del tiempo) y `dropAmt` (entrada OutExpo 320 / salida InQuad 140).
- **Una cosa por pantalla**, dimensionada por `span` (el lado corto), así anda en la vertical.
- La costura se mide: `render.py` compara el cuadro de t=15 con el de t=0 (diferencia 0).

## Los ocho

| kind | qué es | qué lee | costo en el overlay | tubo |
|---|---|---|---|---|
| `swarm` | bandada de punteros de Win95 que en el 1 de cada compás **escribe la palabra que viene** en matriz 5×7, la sostiene tres tiempos y revienta en el cuarto | `nextWord`, `tick`, `high` (tiembla en la subida), `drop` (late) | MShape, ≤ 260 flechas × 3 (estela); `quality` | trinitron / bone |
| `splitflap` | cartel de paletas de aeropuerto: verso N/M, el verso que suena, `SIGUE: <palabra>`; cada cambio gira las paletas en cascada | `lines`, `lineNo`, `nextWord`, `tick`, `drop` | 96 paletas de Text/Rectangle; un recorrido JS toca sólo las que giran | trinitron / dragons |
| `maze` | el Laberinto 3D de Win95: un paso por tiempo por un pasillo en anillo, dobla en las esquinas, la vuelta entera = el loop | `tick`, `drop` (se abre la niebla, se prende el piso), `high` | ShaderEffect de pantalla completa (`maze.frag`, DDA ≤ 40 pasos): el más caro en GPU, casi nada de CPU | trinitron / ado |
| `pipes` | Tuberías 3D de Win95: un caño nuevo cada dos compases, cuatro tramos por tiempo, bocha que late en cada codo; en el último tiempo se limpia la pantalla | `tick`, `drop`, `low` | MShape, 5 capas de profundidad × 8 caños × 3 tonos (cilindro = 3 trazos corridos hacia la luz) | arcade / poison |
| `defrag` | el Desfragmentador de Win95: un movimiento de bloques por tiempo, 0 → 100 % en 30 tiempos, en el 31 se vuelve a fragmentar | `tick`, `drop`, `high` | MShape, ~1300 rectángulos (armados una vez) en 47 tandas + Text | trinitron / vapor |
| `mystify` | "Mystify Your Mind": dos polígonos con estela; el golpe abre la estela, el drop suma un tercero desde el centro | `tick`, `surge`, `energy`, `drop` | MShape, 3 × 22 polilíneas en 15 tandas | arcade / bloodline |
| `vector` | teseracto en monitor vectorial: gira en XW/YZ y pega un octavo de vuelta en cada golpe (8 golpes = 1 vuelta); en el drop, tres entrelazados | `kick`, `tick`, `drop`, `low` | MShape, 32 aristas × 6 (estela) × ≤ 3 | green |
| `harmonograph` | la pluma del harmonógrafo: una roseta por frase, **el trazo engorda donde cayó un golpe** (el compás queda anotado en la figura) | `tick`, `section` (la relación de la figura), `drop` | MShape, ~520 tramos por figura, puntos cacheados por frase | amber |

Cinco son cosas que Windows 95 ponía en un tubo de verdad (`swarm` con sus punteros, `maze`,
`pipes`, `defrag`, `mystify`); los otros tres son máquinas de la época (cartel Solari,
monitor vectorial, harmonógrafo). Ninguno es un espectro de reproductor (regla de `Motif.qml`).

## Cómo se integró (receta para uno nuevo)

1. Copiar a `shell/`: `motifs/<Kind>.qml`, `motifs/MotifBase.qml`, `Ease.js` (y `Dots.js` para
   `swarm`/`splitflap`; `maze.frag` + `maze.frag.qsb` para `maze`). Cambiar los imports
   `"../Ease.js"` → `"Ease.js"`.
2. `Motif.qml`: un `Component` más en el Loader (`motif.kind === "<kind>" ? <kind>C`) que le
   asigne las props como a `Tunnel`/`Static`, más **`clock: motif.clock`**, `bg` (la cara) y
   `running: motif.spinning`.
3. `shell.qml`: sumar el kind a `motifKinds` (de ahí lo lee `fatal crt motif`, `motifs.py`) y a
   un grupo de `motifGroups` (calm: `harmonograph`, `splitflap`; hot: `pipes`, `vector`,
   `mystify`, `maze`; neutral: `swarm`, `defrag`).
4. Dibujar en `onFrame` (techo `stepMin`: 30 Hz en el piso de volumen) con `MShape`, nunca con
   un Canvas de pantalla entera, y probar con `fatal crt motif <kind> --screen all`.
