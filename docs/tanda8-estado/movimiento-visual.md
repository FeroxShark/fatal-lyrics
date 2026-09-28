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

## Banco offscreen (`previews/movimiento/`)

`./render.py sheet [--pace calm|normal|wild]` → `docs/tanda8-estado/movimiento-ritmo.png` (+
`out/metrics.json`); `./render.py cpu [--frames N]`. `Bench.qml` carga el `Mystify` REAL de `shell/`
(deriva por `lt`), sin el vidrio; el ritmo lo calcula `shell/Speed.js` dentro del QML y la fila sale
de `crtPaceTable`. Partitura: a los 240 s de tema, `mov` quieto 1 s → sube en 4 s → arriba 2 s →
baja en 4 s → quieto 1 s (smoothstep). Tres pasadas: `int` (como el overlay), `prod` (control:
reloj de dibujo `t · rate`) y `off` (perilla en 0).

Resultado, pace normal, 721 cuadros a 60 fps:
- Velocidad del reloj de dibujo (s de dibujo por s real): integrado 0.75–1.35, desvío máximo contra
  el `rate` del cuadro **0.0000** (sin saltos de fase); perilla en 0: 1.0 exacto; `t · rate`: de
  **+63× a −63×** (a los 240 s, el cambio de ritmo de la rampa ya teletransporta: corre para
  adelante al subir y para ATRÁS al bajar).
- Cambio de imagen cuadro a cuadro (luminancia media absoluta): integrado media 8.98 / máx 15.9;
  perilla en 0 9.05 / 14.8; `t · rate` 12.2 / 23.3. La tira de cuadros de la hoja muestra la
  estela de Mystify continua en el integrado y deshecha en el control.
- CPU (render offscreen + grab 1280×720, 600 cuadros, dos corridas): perilla en 0 5.38 / 5.44
  ms/cuadro, ritmo andando 5.48 / 5.45 — dentro del ruido (lo agregado son dos multiplicaciones
  por cuadro y por pantalla). No medido en el overlay real (cero corridas en pantalla).

## Falta (para Ferox / con música real)

- Calibrar `movMin`/`movMax`/`PIVOT` con música real (Vivaldi, Invierno): hoy salen de los números
  de `movimiento.md` (parejo ≈ 0.2, ocupado ≈ 0.75-0.8), no de haberlo visto.
- Las entradas y el shader quedaron afuera a propósito (arriba). Si Ferox quiere que la ENTRADA de la
  frase también siga el pasaje, es otra discusión (rompe "UN lenguaje de movimiento").

## Ronda 2: "no se nota" (Ferox, con Vivaldi)

Medido en el sistema vivo (`qs.log` + `.1`, 99 muestras de `mov`, Vivaldi): **p1 0.63, p50 0.73,
p99 0.80**. `mov` vivía en una franja de 0.17 → con el mapeo absoluto (pivote 0.35) el rate salía
1.0–1.2 fijo. Cambios (sólo VELOCIDAD; no se tocó frecuencia de cambios ni entradas):
- **Rangos** (`crtPaceTable`): calm 0.60–1.50, normal 0.40–2.20, wild 0.30–2.80.
- **Percentiles por tema** (`Speed.newStat/observe/span/fit`): histograma de `mov` (40 bins, decae
  τ=60 s, se reinicia con `crtTrackSeed++`, muestreado a 10 Hz), p5..p95 estirado a todo el rango
  (franja mínima 0.20 para no amplificar ruido de un tema parejo), mediana → rate 1 (pivote
  interpolado a 0.5). Arranque: `conf` = masa/20 s mezcla del mapeo absoluto de antes al estirado.
  Vivaldi: 0.63→~0.4×, 0.72→1×, 0.80→~2×. `crt.mov_speed` = 0 sigue siendo ritmo 1 exacto.
  Log de 5 s ahora agrega `span lo-hi`.
- **Radar y lluvia** (`Motif.qml`) llevaban `mclock × velocidad(level, drive)`: aunque `mclock`
  ya seguía el rate, la velocidad variable teletransportaba la fase. Ahora ángulo (`radar.angle`) y
  dos fases (`rain.base`, `rain.kph`) ACUMULADAS con `frameTime · … · rate`.
- Banco (`render.py sheet`, normal): vel. dibujo 0.40–2.20, desvío vs rate **0.0000**; perilla 0: 1.0;
  `t·rate` de −171× a +170×. (El banco usa `mov` crudo, no los percentiles: prueba fase, no calibración.)
- Tests: 769 OK.
