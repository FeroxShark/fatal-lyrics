# Tanda 8 / slice "senales" — estado

Alcance: SOLO `cartelitos/audio.py` + tests. Nada de QML/shaders (eso lo hace otro
worker con lo que este slice exporte). Cero corridas en pantalla — todo se valida
con tests y con el aparejo sintético del repo.

Pedido de Ferox (tras ver tanda 7 con música real):
1. La reacción se siente como "parpadeo de los bajos".
2. No reacciona a silencios secos (cortes de 150-400 ms) ni a su vuelta.
3. Falta algo que siga la música más allá del bajo (brillo/melodía/onsets de agudos).

## Campos nuevos en el evento `aud` (además de los que ya había: l, lo, mid, hi, c, b, h, d, pk)

- `cut` (0/1, sostenido): 1 mientras estamos en un "corte seco" — el tema sonaba y
  cayó a casi nada. Se arma con el `level` ya normalizado contra el pico que sigue
  la propia música (el mismo `an.peak` de siempre), NO contra el rms crudo ni
  contra el percentil del tema (eso es `sec` = quiet de sección, mucho más lento
  y basado en energía relativa al tema entero). Umbrales: entra si `level` está
  bajo `CUT_LOW` (0.06) sostenido `CUT_ENTER_S` (0.10 s, ~3 bloques de 32 ms) DESPUÉS
  de haber estado sonando fuerte (`level > CUT_HIGH`=0.15 hace menos de `CUT_RECENT_S`
  =1.5 s). Esa condición "tenía que estar sonando antes" es la que separa un corte
  seco de un pasaje que ya viene bajito (una `quiet` de sección nunca dispara esto,
  porque ahí `level` no cruzó `CUT_HIGH` recientemente). Sale de la cuenta con el
  primer bloque que vuelve a cruzar `CUT_HIGH` (sin debounce en la salida: el golpe
  de vuelta ES la señal).
- `cutf` (0..1, un solo frame): fuerza del golpe de vuelta. 0 en todos los frames
  salvo el exacto en que `cut` pasa de 1 a 0: ahí vale el `level` de ese frame
  (0..1, ya normalizado). El overlay lo puede usar como "qué tan fuerte pegó al
  volver" para la animación de regreso.
- `hf` (0..1, suavizado): brillo/agudo que CAMBIA, no el brillo en sí (eso ya es
  `c`, el centroide). Es flujo espectral (spectral flux) medido SOLO en la banda
  125-6000 Hz (`DIRT_LO_HZ`/`DIRT_HI_HZ`, ya definidas para `dirt`), es decir "algo
  nuevo entró ahí arriba" — sirve para onsets de platillos/voces/sintes que el
  bajo no toca. Normalizado contra un pico propio que decae (mismo patrón que
  `an.peak` para `level`) y suavizado con EMA asimétrica (sube en ~50 ms, baja en
  ~400 ms) para que sea un pulso con cola, no otro parpadeo. Independiente del
  bajo: un tema con bajo constante y agudos que no cambian da `hf` ~0 aunque
  `level`/`b` estén altos todo el tiempo.
  Costo: NO es una FFT nueva. `dirt` ya llama `power_spectrum(samples)` adentro de
  `spectral_flatness_local`. Se refactorizó para calcular el espectro UNA vez en
  `feed()` y pasarlo a `spectral_flatness_local(samples, rate, spec=spec)` (default
  `None` = lo calcula solo, para no romper los tests/llamadas viejas que le pasan
  sólo samples). `hf` reusa ese mismo `spec` contra el del bloque anterior. Medido:
  ver "Números" abajo.

## Por qué NO se tocó `_capture_loop` casi nada
Sólo se agregó `ev.get("cutf")` a la condición que fuerza el envío inmediato
(antes sólo `ev["b"]`), para que el golpe de vuelta no se demore hasta el próximo
tick de `AUDIO_MIN_SEND` (40 ms, ya bastante corto, pero el golpe de vuelta es un
evento puntual como el beat). Nada más cambia ahí: `cut`/`hf` viajan en todos los
`aud` normales igual que `l`/`c`/`d`.

## Cómo lo va a usar el otro worker (no es tarea mía, pero para que no adivine)
- `cut` sostenido → puede atenuar el tubo mientras dure (como el `dim` del aro).
- `cutf` de un frame → como un golpe (`hit()`), para la animación de vuelta.
- `hf` → un canal de reacción que NO es el bajo: puede mover algo que hoy sólo
  mira `b`/`level`, sin agregar otra animación por pantalla (regla ya existente).

## Hecho

- `cartelitos/audio.py` (e5083ee): `spectral_flatness_local` acepta `spec=None`
  precalculado; `AudioAnalyzer` suma detección de corte/vuelta (`cut`, `cutf`,
  método `_cut_step`) y flujo de agudos (`hf`, `_smooth_hf` + `spectral_flux_band`
  a nivel módulo); `_capture_loop` fuerza envío inmediato en `cutf` (mismo trato
  que ya tenía el beat).
- `tests/test_senales.py` (f0fa8c5), archivo nuevo: 13 tests — corte seco real
  (~200ms) marca `cut=1` y la vuelta trae `cutf>0` una sola vez; blip <0.10s NO
  marca corte; valle de energía que sigue audible (no cerca de silencio) NO marca
  corte; silencio sin haber sonado fuerte antes (arranque/pausa larga) NO marca
  corte; un corte mucho después del último momento fuerte (`CUT_RECENT_S`
  vencido, probado directo contra `_cut_step` porque depende de timing exacto,
  no de cómo decae `an.peak` con un tono sintético) tampoco marca corte; flujo
  espectral: tono estable da flux=0, agudo nuevo sobre bajo constante da flux>0,
  sin espectro previo da 0; `hf`: bajo constante solo asienta cerca de 0, un
  onset de agudos sobre ese bajo lo sube >0.3, y decae a menos de 30% del pico
  al cortarse el onda. Suite completa: 704 tests, OK.

## Fix posterior (encontrado por el slice "movimiento", corregido acá)

`hf` normalizaba contra un pico propio que decae (`flux_peak`, mismo patrón que
`an.peak`). Bug real, mismo patrón que `mov` ya había pisado y corregido: un
pasaje fuerte deja el pico viejo alto y un onset flojo posterior (tras bajar el
volumen) no llega a cruzar el umbral (sordera); y un tono sostenido de fase
continua hace decaer el pico hasta la fuga espectral del propio Hann, con lo
que cualquier bloque normaliza cerca de 1.0 (`hf` clavado en vez de caer a 0 —
el caso de cuerdas nerviosas tipo Vivaldi). Fix: reusa `spectral_flux_ratio`
(la misma técnica de `mov`, normaliza contra la energía ACTUAL del bloque, no
contra un pico viejo) sobre la misma banda 125-6000 Hz. Rango y semántica sin
cambios (0..1, sube en ~50ms, baja en ~400ms) — `shell/React.js` no necesita
recalibrarse. De paso, `mov` deja de calcular su propio término de brillo
aparte: ahora reusa el `hf_raw` que ya calcula `feed()` (antes lo evitaba
justamente para no heredar este sesgo).

Distribución antes/después (aparejo sintético, tono de FASE CONTINUA — con
`tone()`, que reinicia la fase en cada bloque, el bug no se ve: bloques
bit-idénticos dan flujo 0 por construcción):
- Sostenido 220 Hz, amp 0.7, 8 s: `hf` viejo termina en **0.591** (a los 15s,
  **0.922**: sigue subiendo, no converge a 0). `hf` nuevo: **0.000**.
- Pasaje fuerte (bajo+platillo grandes) seguido de bajar el volumen (bajo+
  platillo flojos): pico del onset flojo sobre el piso silencioso, viejo
  **0.473** de salto, nuevo **0.410** de salto — comparable, ya no sordo.
  (Con el bug real de `mov` en su propio slice, el salto viejo podía llegar a
  ser ~0 en vez de sólo algo menor; acá el piso ya estaba bajo por el
  `FLUX_PEAK_DECAY` corriendo sólo ~20 bloques, por eso la diferencia es más
  chica que en el caso sostenido.)

Tests de regresión: `tests/test_senales.py`,
`HfTests.test_a_sustained_in_band_tone_does_not_stay_pinned_near_one` y
`HfTests.test_a_treble_onset_after_the_track_gets_quiet_still_pulses_hf`.
Suite completa: 752 tests, OK.

## Falta / por decidir (default elegido, reversible)

- Nombre de archivo de test: creo `tests/test_senales.py` nuevo (no meto esto en
  `test_dirt.py`, que es de otra corrida) para que quede localizado. Reversible:
  se puede mergear a `test_dirt.py` después sin drama.
- Umbrales (`CUT_LOW`, `CUT_HIGH`, `CUT_ENTER_S`, `CUT_RECENT_S`) elegidos a mano
  contra el sintetizador de test, no contra audio real (no hay pantalla ni
  reproducción en esta tanda). Si Ferox los siente mal calibrados con música real,
  son 4 constantes en un solo lugar, fáciles de tocar.
- No hice captura de audio real del sistema (pw-record) en este slice: no hay
  reproductor sonando garantizado en este entorno de worker y la regla dice cero
  pantalla/mirada — me apoyé en el aparejo sintético (`tests/test_dirt.py` ya
  prueba `AudioAnalyzer` así). Si Ferox quiere números de un tema real, correr
  `pw-record` a un wav y pasarlo por `AudioAnalyzer.feed` en un script aparte
  (no incluido).

## Falta (para el que retome, o para un cierre)

- Nada pendiente de código en este slice: `cut`/`cutf`/`hf` están, testeados y
  medidos. Lo que sigue (usar estos campos en QML) es de OTRO worker/slice.
- No se hizo captura de audio real (ver "Falta / por decidir" arriba): los
  umbrales están calibrados sólo contra el sintetizador. Si con música real
  `cut` tira falsos positivos en pasajes con mucha dinámica (un tema que baja y
  sube de volumen fuerte sin llegar a silencio real), lo primero para tocar es
  `CUT_LOW`/`CUT_HIGH` (más separados = menos falsos positivos, más lento para
  entrar).

## Números (medidos con `timeit` manual, 200 bloques de 32ms con bajo+medio+agudo variable, misma máquina)

- `feed()` ANTES de este slice (commit `0693730`, ya con `dirt`): **0.641 ms/bloque**.
- `feed()` DESPUÉS (con `cut`+`hf`): **0.662 ms/bloque**.
- Diferencia: **+0.021 ms/bloque** (~3.3% relativo), o sea ~0.065% de un núcleo
  extra sobre un hop de 32ms — no se mueve la aguja del ~33% que ya usa el
  overlay. Esperable: `hf` reusa la FFT que `dirt` ya calculaba (no hay una
  FFT nueva), y `_cut_step` es aritmética de cuatro comparaciones.
