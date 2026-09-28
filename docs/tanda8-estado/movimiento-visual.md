# Tanda 8 / slice "movimiento", parte 2/2 (movimiento-visual) — estado

Pedido de Ferox escuchando Vivaldi, Invierno op.8 n.4: el ritmo de las animaciones se
elige por tema (`pace` calm/normal/wild) y no cambia DENTRO de la canción. La señal ya
está (parte 1, `movimiento.md`): campo `mov` (0..1) del evento `aud`, suavizado en el
daemon (sube ~1 s, baja ~3 s). Esta parte la usa para el RITMO de los dibujos.

Cero corridas en pantalla (Fatal Lyrics prendido). `cartelitos/audio.py` no se tocó
(otro worker arregla `hf` en paralelo).

## Diseño

- **`pace` sigue siendo la base; `mov` empuja alrededor de 1.** `shell/Speed.js`
  (`.pragma library`, como `React.js`: overlay y banco llaman a la MISMA función):
  `rate(mov, movMin, movMax, amount)` lineal a trozos — `mov` 0 → `movMin`,
  `mov` = `PIVOT` (0.35) → 1, `mov` 1 → `movMax`. `amount` (perilla) escala la
  desviación desde 1.
- **Pivote 0.35 y no 0.5**: un tema fuerte y PAREJO da `mov` ≈ 0.2 (techo de la
  energía sola) y uno ocupado ≈ 0.75-0.8. Con pivote 0.5 un tema sin mucho movimiento
  correría más lento que hoy de punta a punta. Con 0.35, el tema parejo queda ≈ 0.89×
  (normal) y el ocupado ≈ 1.24×.
- **Rango por fila de `crtPaceTable`** (`movMin`/`movMax`): calm 0.85–1.20, normal
  0.75–1.35, wild 0.60–1.60. Como `dirtMax`/`cutDepth` de la tanda, `wild` se lleva el
  rango más ancho, no el 1/1 de la tanda 3.
- **Perilla `crt.mov_speed`** (0..1, default 1.0; 0 = apagado, ritmo 1 siempre, lo de
  antes). Mismo contrato que `dirt`/`tension`: config.py, ipc.py, setup.py (menú de
  `fatal config`), shell.qml, README.
- **Sin audio vivo el ritmo vale 1 EXACTO** (no `movMin`): sin captura no se sabe
  cómo se mueve nada.
- **NUNCA `t · rate`.** Se integra un DESPLAZAMIENTO: `off += dt · (rate − 1)`
  (`Speed.advance`, que ignora `dt` ≤ 0 o > 0.5 s como `React.grainAdvance`), y el
  reloj de dibujo es `clock + off`. Con rate = 1 es bit a bit lo de antes. El reloj REAL
  no se escala: lo que mide tiempo de verdad sigue leyéndolo.

## Dónde entra el ritmo (y dónde NO)

Entra:
- `Crt.qml` `movOff`: acumulado en los DOS avances de `tubeTime` (FrameAnimation y
  Timer). Lo usan la deriva LIBRE de la barra que rueda (`rollPhaseFor(tubeTime + movOff)`)
  y los motivos sin física propia de `Motif.qml` (`mclock`: radar, lluvia).
- `Motif.qml` pasa `rate` a los ocho con física propia y a los ocho de loop; las
  estrellas multiplican su `frameTime` por `rate`.
- Física propia (Ocean, Dunes, Pond, Static, Rorschach, Plasma, Tunnel, TextSea):
  multiplican el `dt` que ACUMULAN — ya eran integradores. Plasma escala el `dt` del
  resorte (con el mismo tope de 0.05). TextSea sólo sin compás: con `bpmLive` la marea
  va una línea por tiempo, que es el pulso del tema.
- `MotifBase.qml` (los ocho de loop): `movOff` propio acumulado en el mismo commit de
  `clockAcc`; sólo mueve `lt` (lo que deriva).

NO entra (y por qué):
- `tubeTime` / el shader: el zumbido de 60 Hz, la estática, el corte seco, el grano y el
  vigía de `quality` (`healthySince`/`slowSince`) son tiempo real.
- El sync de la letra, el aro-cronómetro (`Ring.qml`), el rayo del salto, `WordSlot`:
  marcan tiempo real. Un test lo controla.
- El compás: `rollPhaseFor` con `bpmLive` sale de `Date.now()`; en `MotifBase`,
  `bp`/`sinceTick`/`ownBeat`, `sinceKick` y `dropAmt` siguen en `clock` real (el reloj
  de `MotifBase` hace doble función: dibujo y tiempo, y es la trampa más fácil de pisar).
- El re-anclaje de `MotifBase` (`|clock − tubeClock| > 0.25 → clock = tubeClock`): si se
  escalara `clock` en vez de sumar un desplazamiento aparte, se despegaría del tubo y
  saltaría un cuarto de segundo cada rato.
- **Entradas: NO.** `Motion.enterMs` está en ~35 sitios con compuertas de tiempo real
  (`Date.now() − textArrivedAt < Motion.enterMs`, el empalme del colapso del aro con la
  entrada de la frase) y es "UN lenguaje de movimiento": escalarlo por tema rompe las dos
  reglas. La entrada ya la decide la música por otro lado (`crtEntryTable`).
- Scope, ojo/ojos, EKG, carta de ajuste: van por `Timer`/`Date.now()` o por la onda real;
  no tienen un reloj de deriva que escalar.

"Una animación por pantalla": no se agrega ninguna; cambia la velocidad de la que ya está.

## Hecho

- `shell/Speed.js` nuevo; `shell/shell.qml` (`audMov`, `crtMovAmount`, `crtMovRate` con
  Behavior `levelMs` en la ENTRADA del integrador, `movMin`/`movMax` en las tres filas,
  log cada 5 s junto al de `dirt`); `shell/Crt.qml`, `Motif.qml`, `MotifBase.qml` y los
  ocho con física propia; `cartelitos/config.py`, `ipc.py`, `setup.py`; `README.md`.
- `tests/test_movimiento_visual.py`: 13 tests (tabla, perilla de punta a punta, cableado,
  lo que NO se escala, y con node: `rate`, `amount`, `advance` y el escalón de ritmo
  integrado vs el producto `t·rate` como control).

## Falta

- Banco offscreen con la tira de frames y CPU antes/después (ver abajo cuando esté).
