# Tanda 8 / slice "reaccion" — estado

Alcance: respuesta VISUAL a las señales nuevas de `aud` (`cut`/`cutf`/`hf`, ver `senales.md`) y
movimiento propio del grano de la estática (`dirt`). No se toca `cartelitos/audio.py`, `shell/fonts/`
ni el tablero de la intro / "SIGUE:". Cero corridas en pantalla: sólo tests y renders offscreen.

## Pedido
1. Silencio seco (`cut`): bajar la luz de los tubos durante el corte y volver con el golpe (`cutf`).
   Inmediato y corto; distinto del `quiet` de sección.
2. Agudos/melodía (`hf`): respuesta PROPIA, distinguible del golpe del bajo, sin romper "una
   animación por pantalla".
3. Estática por suciedad: que el grano se mueva (deriva, ondulación, bandas) y responda más rápido.

## Hecho
Cada canal va en un EJE distinto del golpe del bajo (que es brillo de toda la pantalla), así se
distinguen sin sumar una animación: son parámetros del vidrio que ya se dibuja.

- `34b54c4` `shell/React.js`: funciones puras del reloj del tubo (`cutDim`, `backFlash`, `fizz`,
  `grain`, y en `2bfc513` `grainAdvance`). Las llaman `Crt.qml` Y el banco: la hoja muestra el
  mapeo que corre, no una copia.
- `2e79cc8` `crt.frag` + `.qsb`: uniforms `cutDim`, `backFlash`, `fizz`, `grain` (+ `grainPhase`
  en `2bfc513`). Todos en 0 = salida idéntica a la tanda 7 (diff máx 0, medido).
  - corte: `col *= 1 - cutDim`; vuelta: `col *= 1 + backFlash` + un toque del tinte.
  - agudos: las filas tiemblan de costado (onda + jitter por par de filas, ≤ 2.2 px × fizz) y
    los claros se enfrían (azul +, rojo −, neutro en luminancia). POSICIÓN y COLOR, no brillo.
  - grano: rayas horizontales que derivan de costado, franjas de amplitud que corren hacia
    arriba con un leve ondulado. La CANTIDAD sigue siendo `noiseAmt` × `crtDirtMult`.
- `da1ab6b` `shell.qml`: lee `ev.cut`/`ev.cutf`/`ev.hf` (`audCut`, `audCutF`, `audCutGen`,
  `audHf`, `crtCut = audLive && audCut`, log `crt: cut on|back F`); filas de pace
  `cutDepth`/`cutFlash`/`fizzAmt`/`grainMove` (calm < normal < wild); `Behavior on crtDirt`
  de `Motion.holdMs` (1500) a `Motion.levelMs` (420): el grano sigue a la suciedad más rápido.
- `5c5a1e0` `Crt.qml`: `cutAt`/`backAt` se sellan con `tubeTime` (Connections a `crtCut` y
  `audCutGen`); duraciones de `Motion` (bajada `exitMs`, tope `holdMs`, suelta `levelMs`,
  vuelta `enterMs`). Gate `reactOn` = tubo vivo, no oscuro y `crtFlicker > 0.01`.
- `2bfc513` fase del grano ACUMULADA en QML (ver Aprendido).
- `5580914` banco `previews/reaccion/` (`render.py sheet|cpu`, partitura `Score.js`).
- `46d9a72` hojas `reaccion-corte.png`, `reaccion-agudos.png`, `reaccion-grano.png` (pace normal).
- `e8d05fd` `tests/test_reaccion.py` (9 tests: cableado, qsb, filas, React.js con node). Suite
  completa: 718 OK.

### Números (banco offscreen, pace normal)
- Corte: brillo medio durante el corte 1.003 → 0.479 del de antes; pico de vuelta 1.147 → 1.594.
- Golpe de bajo (a flicker 1): brillo +10.0 %, cambio local rms 2.6, azul−rojo en claros −4.7.
- Agudos: brillo +0.08 %, cambio local rms 3.8, azul−rojo en claros +25.9. Se distinguen.
- Grano (dirt 0.9, motivo, arcade): contraste de franjas 0.067 → 0.32.
- CPU (render offscreen + grab, 300 cuadros, motivo arcade): 18.5 → 17.6 ms/cuadro, ruido. El
  banco no es el overlay: lo que suma el overlay es 4 bindings y un handler en `onTubeTimeChanged`
  por pantalla, y ALU del shader dentro de `if (grain>0.001)` / `if (fizz>0.001)`. No se midió
  en el overlay real (regla: cero pantalla).

## En curso
(nada)

## Falta
- Verlo con música real en la pared (lo hace Ferox o el jefe al integrar): sobre todo si el
  temblor de agudos en `wild` (fizz 1.0) queda demasiado.
- Hojas en `calm`/`wild`: `./render.py sheet --pace calm --suffix -calm` (no commiteadas).

## Supuestos
- Sin perilla nueva en el TOML: las intensidades salen sólo de `pace` (sumar una toca
  `config.py`, el menú y `ipc`; fuera del slice). `wild` = los valores más fuertes, como `dirtMax`.
- Un corte más largo que `Motion.holdMs` es una pausa: la luz vuelve sola en `levelMs` (la pausa
  larga la maneja `resting`). También cubre un `audLive` vencido que no se reevalúa.
- `reactOn` exige `crtFlicker > 0.01` (quien apagó el parpadeo no quiere la luz moviéndose) pero
  NO escala por `flickerAmt`: con el default 0.25² el golpe del bajo es chico y el corte se vería
  apenas.
- Las pantallas `tubeDark` no reaccionan; el corte baja también las pantallas con motivo.
- Agudos en pantallas sin foco al 60 % (como `pulse`).
- `Behavior on crtDirt` 1500 → 420 ms: el daemon ya suaviza `d`; el pedido era responder más rápido.

## Aprendido
- Comparar cuadros de `t` distintos está contaminado por el parpadeo de 60 Hz del shader: cada
  canal se mide contra el MISMO `t` sin ese canal (golpe con `pulseOff`, agudos antes vs ahora).
- `t · velocidad(x)` en un shader con `t` en cientos de segundos: cualquier cambio chico de `x`
  corre la fase de golpe. La fase se acumula en QML (`React.grainAdvance`) y viaja como uniform.
- El quimógrafo (amplitud del ruido por fila × tiempo) es lo que muestra el movimiento del grano;
  los cuadros sueltos casi no lo dejan ver.

## Cómo retomar
- `git log --oneline 521e66a..HEAD`
- Hojas: `cd previews/reaccion && ./render.py sheet [--pace calm|wild --suffix -x]` (~8 min).
  CPU: `./render.py cpu`. El "antes" es `git show 521e66a:shell/crt.frag.qsb`.
- Tests: `python3 -m unittest discover -s tests -p test_reaccion.py`.
