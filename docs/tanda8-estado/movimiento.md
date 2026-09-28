# Tanda 8 / slice "movimiento" — estado (parte 1/2: señal)

Alcance de esta parte: SOLO `cartelitos/audio.py` + tests. Nada de QML/shaders (lo
usa otro worker con lo que este slice exporte, en la parte 2). Cero corridas en
pantalla ni reinicios del daemon (Fatal Lyrics está prendido) — todo se valida con
el aparejo sintético del repo (mismo patrón que `tests/test_senales.py`).

Pedido de Ferox (escuchando Vivaldi, Invierno op.8 n.4: cuerdas rápidas y
nerviosas, casi sin bajo ni batería): la VELOCIDAD de las animaciones no sigue los
cambios DENTRO de una canción — hoy el ritmo (`pace`) y el mood se eligen POR TEMA
una vez, con `energy` global. Falta una señal continua de "cuánto se está moviendo
la música ahora mismo".

## Campo nuevo en el evento `aud`

- `mov` (0..1, suavizado): cuánto se está moviendo la música EN ESTE MOMENTO.
  Combina tres cosas, pesadas (no un OR, ver abajo por qué):
  - **Densidad de onsets en TODO el espectro** (peso 0.5, `MOV_W_DENS`): no sólo
    el bajo — la clásica no tiene bombo. Se mide flujo espectral (mismo mecanismo
    que `hf`, `spectral_flux_band`) pero en la banda `MOV_FLUX_LO_HZ`-`MOV_FLUX_HI_HZ`
    (40 Hz al Nyquist, o sea CASI todo el espectro, incluido el bajo — a
    diferencia de la banda de `hf`, que arranca en 125 Hz para no mezclarse con
    `dirt`). Cada vez que el flujo normalizado (contra un pico propio que decae,
    `mov_flux_peak`) pasa `MOV_ATTACK_THRESH` y ya pasó el refractario
    `MOV_ATTACK_REFRACTORY` (50 ms: cuerdas rápidas pueden ir a 10-15 onsets/s),
    cuenta como un "onset". Los onsets alimentan un contador que decae solo
    (EMA de impulsos, ventana `MOV_RATE_TAU`=1.2s) — eso es la DENSIDAD, no la
    magnitud de un solo golpe: un tremolo de notas chiquitas sube esto tanto como
    pocos golpes grandes, que es justo lo que un `beat` de bajo no ve.
  - **Brillo que cambia** (peso 0.3, `MOV_W_BRIGHT`): mismo CONCEPTO que `hf`
    (flujo de agudos, banda 125-6000 Hz) pero NO es el campo `hf` reusado — ver
    "Bug encontrado y corregido" más abajo, importante.
  - **Energía relativa al PROPIO tema** (peso 0.2, `MOV_W_ENERGY`): el percentil
    que ya calcula `classify_level(rms, TrackProfile.rms)` — el mismo número que
    ya usa `PeakGate` (`cur_pct` en `_capture_loop`) — NO el nivel crudo. Así un
    tema tranquilo entero también tiene sus picos relativos, en vez de que todo
    quede bajo porque nunca suena "fuerte" en términos absolutos. Sin perfil
    todavía (arranque del tema, o sin posición del reproductor), cae a `level`
    (el nivel ya normalizado contra el pico que decae, `an.peak`) — sigue siendo
    0..1 y razonable, sólo menos preciso.

  Por qué PESADO y no un OR (`1-(1-a)(1-b)(1-c)`): un tema fuerte y PAREJO —sin
  onsets nuevos, sin cambio de brillo— no tiene que quedar "clavado arriba" sólo
  porque suena fuerte (pedido explícito de Ferox). Con un OR, el término de
  energía por sí solo ya empuja `mov` cerca de 1. Pesado (energía sólo 0.2), el
  techo que puede dar la energía SOLA es 0.2 — ver el test
  `test_a_loud_but_steady_track_does_not_stay_pinned_high`.

  Suavizado: EMA asimétrica igual que `dirt`/`hf` pero con ventana grande
  (`MOV_RISE_S`=1.0s subiendo, `MOV_FALL_S`=3.0s bajando — ventana total ~2-4s
  pedida por Ferox): sube en ~1s así un pasaje que se acelera se nota rápido,
  baja mucho más lento para que no sea "otro parpadeo".

  Costo: NO hay FFT nueva. Reusa el mismo `spec`/`prev_spec` que ya calculan
  `dirt` y `hf` (ver el comentario junto a `FLUX_LO_HZ` en el código) — sólo se
  suma un tercer `spectral_flux_band` sobre una banda más ancha (misma FFT).
  Medido: ver "Números" abajo.

## Por qué NO se tocó casi nada de `_capture_loop`

Sólo el llamado a `feed()` pasa ahora `pct=cur_pct` (el percentil que YA se
calculaba ahí para `PeakGate`, una asignación existente reusada, no una cuenta
nueva). `cur_pct` sigue siendo el del bloque anterior (mismo desfase de hasta
`PROFILE_STEP`=0.5s que ya tenía `gate.hit()`) — no hace falta más precisión: el
suavizado de `mov` ya tiene una ventana de segundos.

## Tempo local: NO se hizo (opcional, descartado por ahora)

Ferox lo pidió como opcional "si sale robusto y barato". Ya existe `BpmTracker`
(histograma de intervalos entre `beat`s) pero está armado sobre el `beat`
broadband (refractario 250ms, pensado para percusión/bombo) y vive en
`_capture_loop`, no en `AudioAnalyzer`; adaptarlo a onsets de arco (mucho más
densos y menos regulares que un bombo) es un histograma nuevo, no una reutilización
barata, y el resultado con cuerdas sin pulso claro (rubato) sería poco confiable
— exactamente el caso que motivó el pedido. La densidad de onsets (`mov`) ya es
un proxy barato de "qué tan rápido va esto" sin prometer un BPM que puede mentir.
Si Ferox lo quiere igual, es un slice aparte.

## Bug encontrado y corregido (normalización contra un pico que decae)

La primera versión de `_mov_step` normalizaba el flujo espectral contra un pico
propio que decae (`mov_flux_peak`, igual que hace `hf` con `flux_peak`). Un
`advisor()` en este slice marcó dos fallas del patrón, y ambas se confirmaron
con un tono sostenido de FASE CONTINUA (no `tone()` del test rig, que reinicia
la fase en cada llamada y da bloques bit-idénticos — flujo 0 por construcción,
no prueba nada):

1. **Sordera después de bajar el volumen** — el caso Vivaldi real: un pasaje
   `ff` deja el pico alto, y onsets genuinos de un pasaje `mf` que sigue no
   llegan a cruzar el umbral (normalizado contra el pico viejo) hasta que el
   pico decae, ~varios segundos. Medido ANTES del fix: un tren de onsets fuerte
   seguido del mismo tren flojo daba `mov` muy distinto entre los dos tramos.
   Después del fix: 0.795 vs 0.754 (parecido) — test
   `test_loud_then_quiet_onsets_at_the_same_rate_give_similar_mov`.
2. **Clavado arriba con tono sostenido** — con un tono de fase continua a
   `pct=1.0` durante 90s, `mov` quedaba en ~0.972 en vez de bajar al techo de
   energía (~0.2): el pico decae hasta la magnitud de la fuga espectral del
   propio Hann (inevitable si el período no entra un número entero de veces en
   el bloque) y de ahí en más CUALQUIER bloque normaliza cerca de 1.0.

**Fix**: nueva función `spectral_flux_ratio(spec, prev_spec, rate, lo_hz,
hi_hz)` — mismo flujo semirrectificado que `spectral_flux_band`, pero
normalizado contra la energía ACTUAL del bloque (`sum(sqrt(spec[lo:hi]))`), NO
contra un pico que decae. Invariante a escala: un onset desde silencio da ~1.0
sin importar el volumen absoluto, y una señal sostenida da ~0.0 sin importar
cuánto tiempo tuvo el pico para decaer. Se usa para el término de densidad
(banda completa) Y para el de brillo (ver abajo). `MOV_ATTACK_THRESH` se
recalibró de 0.35 (escala vieja, relativa al pico) a 0.12 (escala nueva,
relativa a la energía del bloque).

**Hallazgo colateral, NO corregido acá**: el campo `hf` del evento (de OTRO
slice ya cerrado, "senales") tiene el MISMO bug — con el tono sostenido de fase
continua, `hf` queda clavado en ~0.85-0.93 en vez de caer a 0, porque
`self.flux_peak` (decay 0.97) también decae hasta la fuga del Hann. Como el
primer diseño de `mov` reusaba `hf` directo (peso 0.3), heredaba el sesgo:
`mov` quedaba en ~0.47 en vez de ~0.2 para un tema sostenido. Corregir `hf` es
de otro slice, ya testeado y calibrado — no se tocó acá. En cambio, `mov`
calcula su PROPIO término de brillo con `spectral_flux_ratio` sobre la misma
banda (`DIRT_LO_HZ`-`DIRT_HI_HZ`, 125-6000 Hz) — mismo `spec`/`prev_spec`, sin
FFT nueva — suavizado con su propio estado (`mov_bright`/`mov_bright_at`,
`_smooth_mov_bright`, mismas constantes de ventana que `hf`:
`MOV_BRIGHT_RISE_S`=`FLUX_RISE_S`, `MOV_BRIGHT_FALL_S`=`FLUX_FALL_S`). Si algún
día se corrige `hf` en su propio slice, `mov` podría volver a reusarlo — no es
urgente, el costo de tenerlo aparte es despreciable (mismo FFT, un
`spectral_flux_ratio` más).

Verificado con tono sostenido de fase continua, `pct=1.0`, 30s: `mov` converge
exactamente a 0.2 (el techo de energía sola) mientras `hf` se queda en
~0.85-0.93. Test `test_a_loud_but_steady_track_does_not_stay_pinned_high`
reescrito para usar `sustained()` (fase continua) en vez de `tone()`.

## Hecho

- `cartelitos/audio.py`: función módulo `spectral_flux_ratio` (flujo
  normalizado contra la energía del bloque ACTUAL, no un pico que decae — ver
  "Bug encontrado y corregido"); constantes `MOV_*`; estado nuevo en
  `AudioAnalyzer` (`mov_rate`, `mov_rate_at`, `mov_last_attack`, `mov_bright`,
  `mov_bright_at`, `mov`, `mov_at`); métodos `_mov_step` (densidad de onsets
  banda completa), `_smooth_mov_bright` (brillo invariante a escala, propio de
  `mov`) y `_smooth_mov` (EMA asimétrica final); `feed()` con parámetro nuevo
  `pct=None` y campo `mov` en el evento; `_capture_loop` pasa `pct=cur_pct` al
  llamado a `feed()`.
- `tests/test_movimiento.py`, archivo nuevo: 8 tests — pasaje que acelera sin
  cambiar volumen sube `mov`; trémolo agudo sin nada de bajo también lo sube
  (>0.4); silencio lo mantiene en 0.0 todo el tiempo; tema fuerte y PAREJO
  (tono de fase continua, no `tone()`) con `pct=1.0` (peor caso) queda bajo
  0.35, lejos de clavarse arriba; onsets a la misma densidad fuerte-luego-flojo
  dan `mov` parecido (el caso Vivaldi real, regresión del bug de abajo); sin
  `pct` (perfil desconocido) no explota y sigue en 0..1; sube apreciablemente
  (>0.15) en el primer segundo de un pasaje ocupado; y al cortarse ese pasaje
  sigue por encima del 40% de su pico un segundo después (baja más lento de lo
  que subió). Suite completa: 732 tests, OK.

## Cómo lo va a usar el otro worker (no es tarea mía, pero para que no adivine)

- `mov` es un reemplazo/complemento de "energía global del tema" para decidir
  la VELOCIDAD de lo que ya se dibuja (cuántos cuadros de una animación, cada
  cuánto puede repetirse un evento dentro del presupuesto de `pace`), no una
  animación nueva ni otra regla de "una animación por pantalla": sigue siendo
  UN número que ya viaja en el evento `aud` de siempre, como `l`/`c`/`hf`.
  Con `pace` (`crtPaceTable`) fijando el TECHO de cuántas cosas pueden pasar
  por minuto, `mov` puede modular DENTRO de ese techo qué tan seguido se llega
  a él en cada momento — sin agregar otro parpadeo, porque ya viene suavizado.

## Números (medidos con `timeit` manual, 200 bloques de 32ms, bajo+medio+agudo variable, misma máquina)

- `feed()` sin el cálculo de `mov` (`_mov_step` parcheado a no-op, mismo proceso
  para que sea comparable): **0.690 ms/bloque**.
- `feed()` con `mov` completo (densidad banda completa + brillo propio vía
  `spectral_flux_ratio`, sin reusar `hf`): **0.786 ms/bloque** (re-medido tras
  el fix del bug, que agrega un segundo `spectral_flux_ratio` para el término
  de brillo — antes del fix, que reusaba `hf` ya calculado, daba 0.702-0.728).
- Diferencia: **+0.1 ms/bloque** (~14% relativo) contra el `feed()` sin `mov`,
  bien por debajo del ~33% de un núcleo que ya usa el overlay con audio
  prendido. Sigue sin haber FFT nueva: todo reusa el mismo `spec`/`prev_spec`
  que ya calculan `dirt`/`hf`, sólo se suman dos pasadas O(bins de la banda)
  sobre arrays ya calculados (raíces cuadradas + sumas).

## Falta / por decidir (default elegido, reversible)

- Pesos (`MOV_W_DENS`=0.5/`MOV_W_BRIGHT`=0.3/`MOV_W_ENERGY`=0.2) y umbrales
  (`MOV_ATTACK_THRESH`, `MOV_RATE_REF`, `MOV_RATE_TAU`) calibrados a mano contra
  el sintetizador de test, no contra audio real (no había música sonando en este
  entorno al momento del slice — `playerctl status` daba `Paused`). Son 6
  constantes en un solo lugar del módulo si Ferox los siente mal calibrados con
  música real, sobre todo con clásica de verdad (Vivaldi) en vez del aparejo
  sintético.
- Nombre del campo: `mov` (corto, como `l`/`c`/`d`/`hf`). Reversible, es un
  string en un dict.
- `pct=None` como default de `feed()`: reversible, no rompe callers viejos
  (`test_dirt.py`/`test_senales.py` siguen llamando `feed(pcm, t)` sin tercer
  argumento).

## Ronda 3 (2026-09-28): la señal, más rápida y sin saturar

Ferox, con música real: "se ve el cambio pero es mínimo, más sensible al ritmo". Cambió `cartelitos/audio.py`:
`MOV_ATTACK_THRESH` 0.12 → 0.45 y la densidad pasa a ser compresiva (`1 − exp(−n/MOV_RATE_REF)`); ventana de
onsets `MOV_RATE_TAU` 0.6 s; término nuevo `MOV_W_BEAT` (densidad de `beat`s, ventana 1.5 s); pesos
0.35/0.20/0.25/0.20; suavizado `MOV_RISE_S` 0.25 / `MOV_FALL_S` 0.7 (lo de arriba dice 1.0 / 3.0: quedó viejo).
Tempo local: sigue descartado (`BpmTracker` no lee cuerdas rápidas). Números: `docs/NUMEROS-MEDIDOS.md`.

