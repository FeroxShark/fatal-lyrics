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
  - **`hf`** (peso 0.3, `MOV_W_HF`): el flujo de agudos que YA existe (brillo que
    cambia, 125-6000 Hz), reusado tal cual, ya suavizado.
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

## Hecho

- `cartelitos/audio.py`: constantes `MOV_*`, estado nuevo en `AudioAnalyzer`
  (`mov_flux_peak`, `mov_rate`, `mov_rate_at`, `mov_last_attack`, `mov`, `mov_at`),
  método `_mov_step` (densidad de onsets banda completa) + `_smooth_mov` (EMA
  asimétrica), `feed()` con parámetro nuevo `pct=None` y campo `mov` en el evento;
  `_capture_loop` pasa `pct=cur_pct` al llamado a `feed()`.
- `tests/test_movimiento.py`, archivo nuevo.

(el resto de esta sección se completa a medida que se commitea cada bloque)

## Falta / por decidir (default elegido, reversible)

- Pesos (`MOV_W_DENS`=0.5/`MOV_W_HF`=0.3/`MOV_W_ENERGY`=0.2) y umbrales
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
