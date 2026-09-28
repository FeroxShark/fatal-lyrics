# cartelitos — Números medidos

Mediciones de CPU/latencia y cómo se tomaron. Los números nuevos van acá.
Movido tal cual desde `CLAUDE.md` el 2026-09-05.

- **El presupuesto de eventos, medido con `docs/plans/pace-count.py`** (tema falso de 90 s, un
  verso cada 3 s, tres pantallas, secciones cada 13 s, un pico cada 12 s). Antes de la corrida 3
  de la tanda 4: **89** cambios de dibujo (30 por pantalla: uno por verso), **55** roturas,
  **2** cambios de canal, con el color de la pared dándose vuelta en cada pico. Después, en
  `normal`: **14 cambios de dibujo en 60 s** (uno cada 12.8 s por pantalla) y el resto contra los
  porteros de la tabla. `wild` devuelve los números de antes.
- La corrida 2 de la tanda 3 NO subió el costo: con un aparejo fijo (motivos forzados por la
  letra, un verso cada 2 s, ocho muestras de 8 s) el overlay pasó de **41 %** de un core a
  **35 %**. Baja sobre todo porque la grilla de ojos eran quince Canvas y ahora son cuatro; lo
  que se agregó (las hebras del aro, el rayo del salto) dura menos de medio segundo por verso.
- CRT prendido, baseline de la corrida 4 de la tanda 4 (`docs/plans/cpu-bench.py`, dos corridas
  de ocho muestras de 8 s, tres monitores, Spotify PARADO): **31-53% de un core**, media
  **41%** (39.1 y 42.9 las dos corridas). El aparejo fuerza los motivos caros por la letra
  (tunnel / rorschach / ekg) y manda un verso cada 2 s, así que es el techo, no el uso normal.
  Es el número contra el que se compara de acá en adelante: el "20-37%, media 29" viejo se
  midió con otro aparejo y no es comparable. Apagado: 1.7% (sin captura, sin texturas).
  El overscan de la tanda 3 (la cámara alejando hasta 0.82 y dibujando 1.5× de área) ya no
  existe desde la corrida 1.
- **Al CERRAR la corrida 4 de la tanda 4, mismo aparejo y Spotify parado: 17-39% de un core,
  media 27%** (26.2 y 27.9 las dos corridas). Baja un tercio contra el baseline de arriba y
  **la causa NO está medida**: esta corrida no optimizó nada — la arena recorre más lejos
  (`ZMAX` 16 → 34), el hiperespacio pasó de 46 items a 110 y la carta de ajuste AGREGÓ un
  Canvas. Los sospechosos son el estado del aparejo y que el baseline se tomó con el
  `dunes.frag` a medio hacer del worker anterior cargado. Antes de festejar la baja, medir de
  nuevo con el mismo `cpu-bench.py` en frío.
- **Corrida 5 (túnel de verdad), mismo aparejo, Spotify parado: 22-39% de un core, media 30%**
  (29.3 y 30.6 las dos corridas). Sube ~3 puntos contra el cierre de la corrida 4: el sospechoso
  es que el túnel ahora evalúa la pared DOS veces (el barrido del drop), y es uno de los tres
  motivos que el aparejo fuerza. Es el número vigente; falta re-medirlo en frío sin el aparejo
  forzando motivos caros (pendiente, ver abajo).
- **Base de la tanda 7 (corrida 0, 2026-09-25, con el `tint` ya conectado; Spotify PARADO,
  tres monitores, `docs/plans/cpu-bench.py --scenario X`, ocho muestras de 8 s, `quality` 1.0):**
  - `techo` (el aparejo de siempre: motivos forzados, `focus = all`, verso cada 2 s):
    **25-28%, media 27.4%**.
  - `normal` (verso cada 4 s, sin motivos forzados, `focus` y cámara de fábrica, `aud` a 15 Hz
    y `pos` cada 1 s): **28-32%, media 29.8%**. Con `--quality 0.75`: 27-32%, media 28.9%
    — el corte de calidad apenas mueve la aguja, así que el costo no está en la textura.
  - `pausa` (letra puesta, sin `aud` ni `pos`): **24-25%, media 24.5%**. Es la mayor parte del
    costo: en pausa el tubo sigue dibujando a pleno (`FrameAnimation` sin tope, timer `pump`
    de 70 ms; ver el plan de la tanda 7, corrida 8).
  - Ojo: `normal` sale MÁS caro que `techo`. Sospecha, NO medida: el `aud` a 15 Hz y el
    `focus = roam` cuestan más que los motivos forzados (`normal` a 1.0 y a 0.75 dan lo mismo,
    pero `techo` se midió una sola vez). Estos tres son el número contra el que cada corrida de
    la tanda 7 puede sumar como máximo +3 puntos; el ruido entre corridas ronda ±2.
- **Tanda 7, corrida 1 — dos pasadas + señal compuesta** (`cpu-bench.py`, 8×8 s, Spotify en
  pausa, misma sesión). Base re-medida con el commit anterior (una pasada): `techo` **29.3%**,
  `normal` **29.6%** (la base de la corrida 0 dio 27.4 y 29.8: el ruido entre sesiones es de
  ±2, así que la comparación buena es la de la misma sesión).
  | `crt.composite` | `techo` | `normal` |
  |---|---|---|
  | 0 (pasada vacía, passthrough) | 30.4% | 30.7% |
  | 0.5 (TV vieja, el default) | 30.5% | 29.6% |
  | 1 (VHS) | 30.2% | 30.0% |

  La pasada vacía cuesta ~**+1.1** (techo) y ~+1.1 (normal) sobre la base de la misma sesión;
  contra la base de la corrida 0 el techo sube +3.0 (justo el tope, pero con ese ruido). Los
  niveles de `composite` no se distinguen entre sí (±1): lo que cuesta es tener la segunda
  textura, no las 8 muestras. No se puso detrás de `crtQuality >= 1`. NO medido: `--quality 0.75`
  (con `crtQuality < 1` el paso bajo de chroma baja a 3 muestras).
- **Tanda 7, corrida 2 (tubos), CPU total de qs, cpu-bench:** el tubo no cuesta nada medible (±1).

  | tubo   | techo | normal |
  |--------|-------|--------|
  | custom | 29.3  | 30.4   |
  | pvm    | 29.7  | 29.3   |
  | arcade | 29.8  | 30.2   |
  | green  | 29.9  | 29.6   |

  La base de la corrida 1 era 29.3 / 29.6. Cambiar de tubo es un `case` de uniforms (máscara,
  mono) sobre la misma pasada de vidrio: no hay textura ni muestras nuevas. Ojo con medir con la
  máquina cargada (salieron ~45% descartados) y con que el daemon se muere solo tras una pausa
  larga de Spotify: `fatal on` antes de cada corrida o `cpu-bench` falla con `qs.pid` faltante.
- **`ENERGY_GAIN_REF` (mood.py), medido en vivo el 2026-09-16:** ganancia lineal real 0.064,
  de Spotify con el stream al 40% (`0.40**3` — la escala de PipeWire/pactl es CÚBICA, no
  lineal, ver docs/TRAMPAS.md) sobre el sink de Ferox (Kingston HyperX USB, `HW_VOLUME_CTRL`:
  el volumen del SINK no entra, se aplica en hardware después de donde `pw-record` engancha
  el monitor — medido: 100%→30% de sink apenas movió el rms capturado, 0.4109→0.4066). Es la
  referencia contra la que `mood.energy()` reescala FLOOR/CEIL para perfiles con `gain`
  guardado: un solo dato, no una distribución — si el volumen habitual de escucha cambia
  mucho, remedir.
- El análisis de audio es Python puro sobre `pw-record` (sin cava, sin numpy): 0.79% de CPU.
  Arma el mapa del tema por percentil de energía dentro de la propia canción
  (quiet/verse/build/drop) y lo cachea: la segunda vez que suena, anticipa los golpes.
- **Tanda 6, corrida 6, paso 2 — línea entera de 12 palabras en allMode, 3 pantallas**
  (`docs/plans/cpu-bench.py` adaptado: `crt_focus: "all"` + línea fija de 12 palabras, ocho
  muestras de 8 s). ANTES (Text de una pieza, commit `4825d55`): **11-14%, media 12.7%**.
  DESPUÉS (Flow de `WordSlot` por palabra, commit `9971987`): **17-17%, media 17.1%**. Sube
  **4.4 puntos**, más del tope de 3 del plan: el Flow quedó atrás de `crt.wholeWordsOn`
  (`crtQuality >= 1`), con el Text de una pieza de fallback cuando la pantalla ya viene lenta
  y `crtQuality` bajó sola (`Crt.qml` línea ~1077).
- **Tanda 7, corrida 3 — estela del fósforo (`crt.persistence` 0.35, `docs/plans/persist-drive.py`).**
  Vida media DIBUJADA en pantalla (wf-recorder sin pérdida de una caja de ≤240 px sobre la tinta,
  cara oscura, cambio de "M…" a "i", curva normalizada por canal, interpolada entre cuadros):
  mitad ≤ 37 ms en verde y ≤ 27 ms en rojo/azul en todas las corridas (umbral 90 / 60);
  al 10% ≤ 152 ms y al 2% ≤ 275 ms (umbral: no sobrevivir a `Motion.enterMs`, 320). La última
  corrida dio, DP-4 (60 Hz) r/g/b: mitad 9/10/12 ms, 10% 91/95/91, 2% 154/164/156;
  DP-5 (144 Hz) r/g: mitad 12/9, 10% 120/152, 2% 152/209. Iguales a 60, 144 y 200 Hz (el `dt`
  sale de `frameSwapped`). La curva cae de golpe en el primer cuadro (1.0 → ~0.55 dibujado) y
  después arrastra una cola: el vidrio (bloom + curva) aplasta la estela, por eso queda sutil.
  Texto quieto: |estela prendida − apagada| (2.2 / 1.7 de media en DP-4 / DP-5) queda dentro del
  ruido prendida-prendida (2.8 / 2.0): invisible.
  CPU: sin costo medible. A/B intercalado (persistence 0 contra 0.35, mismas condiciones):
  techo 46.4 → 44.7, pausa 26.1 → 25.7, instrumental (dunes en todas) 40.5 → 40.0. Los niveles
  absolutos están inflados por carga externa (la base de la corrida 0 era 27.4 / 29.8 / 24.5);
  vale la diferencia, que cae dentro del ruido y del tope de +3. Una primera corrida quedó
  inválida: las capturas bajaron `crtQuality` y la estela se apagó sola.
- **Tanda 7, corrida 4a — tensión hacia el estribillo (`crt.tension` 1.0, `docs/plans/chorus-drive.py`).**
  CPU: A/B intercalado (tension 0 contra 1, mismo momento, con estribillo sintético x3): +1.4
  puntos, dentro del ruido y del tope de +3. Carga externa fuerte durante la medición (load
  ~1.7–1.9), así que los absolutos no valen, sólo la diferencia. Curva (`crt: tension` cada 5 s):
  sube con `posAbs` hasta `crtClimaxT` (t0 de la última ocurrencia de la línea más repetida),
  escalón mientras suena el `chorus`, baja ×0.3 en el outro; con `crt.tension = 0` `mult` vale 1.
  Rangos de `crtTensionMult` (pace): calm 0.92–1.12, normal 0.80–1.30, wild 0.60–1.70.

## Quemado del estribillo (tanda 7, corrida 4b)

- Contraste máx. sobre cara oscura (captura, zona 86% del recorte): burnin 0.5 = 4.1–4.5 %, burnin 1 =
  8.2–8.3 %; piso de ruido (0 vs 0 bis) < 0.65 %. Techo pedido: 5 % / 10 %. **Ajuste post tanda 7**
  (Ferox: "molesto"): techo 0.06 × perilla → ≈ 2.5 % a 0.5 y ≈ 3.3 % a 1 (medido por mediana de cuadros
  contra la perilla en 0; el piso de ruido del tubo, 0.5–3 %, limita la precisión). Ciclo de vida
  on/hold/fade/clear: fantasma visible a +1 s, ya sin nada a +3 s del fin del estribillo (fade 2 s).
- CPU A/B burnin 0 vs 0.5: +1.9 / −0.5 puntos, ruido. Carga externa 14–20 (load average).

## Glitches en el tiempo (tanda 7, corrida 5a, `crt.beat_lock`)

- `beat-drive.py 40 120` (bpm sintético 120, `pace = wild`, un verso cada 2.63 s): desfase entre el
  glitch `src=line` y el tiempo, medido por el log del overlay (`beat+<ms>`) y por el reloj del
  driver (lee el log cada 2 ms): mediana 7–10 ms, ~80 % bajo 30 ms, peor 33 ms (log) / 55 ms
  (driver, suma la latencia del socket del `bpm`). Los que pasan de 30 son cuadros colgados del
  hilo gráfico. Sin beat_lock las fases se reparten en ±250 ms. Objetivo pedido: < 30 ms.
- CPU A/B `beat-drive.py cpu 4 12` (beat_lock false/true intercalado, compás vivo, una línea cada
  4 s): 26.6 % contra 27.1 % de un núcleo, +0.56 puntos (ruido). Carga externa 2.1–2.3.
- CPU A/B `fx-drive.py cpu 3 12` (corrida 5b, `crt.word_fx` false/true intercalado; PEOR caso: `pace = wild`,
  un verso con `fire` cada 2 s, o sea un efecto por verso, 6 por ronda): 30.8 % contra 32.6 % de un núcleo,
  +1.8 puntos. Carga externa 2.4–5.9 (alta: ruido de ±2 puntos entre rondas iguales, 29.7–32.5 con la perilla
  apagada). En uso normal (`fxGapMs` 6000, palabras clave raras) el costo es cero salvo el instante del efecto.
- `rollPhase` por compases (corrida 5b) no cambia el costo: la cuenta es la misma, un módulo más.

## Intro v2: degauss + carta de ajuste (tanda 7, corrida 6, `crt.intro_card`)

- CPU A/B de la tarjeta sostenida (`intro2-drive.py cpu`, `intro_card` plain/testcard intercalado, con la
  tarjeta en pantalla): plain 27.4 % contra testcard 22.3 % de un núcleo, −5.1 puntos (la carta de ajuste no
  es más cara que los textos planos; el orden intercalado y el ruido explican el signo). Carga externa 2.4–4.1.
- El degauss (700 ms, sólo dentro de la intro) es un `if (degauss > 0.001)` uniforme-coherente en `crt.frag`:
  no se pudo A/B en el mismo momento (el shader viejo no se puede alternar). `cpu-bench --scenario normal`
  con el shader nuevo: 38.6 % (rango 29–58) y 35.1 % (rango 29–44); vesktop sostenía 47 % y la carga externa
  era 2.2–3.8, contra la base de 29.6–30.7 % de las corridas 0–2. Ruido de la máquina, no atribuible.
- Estrés on/off: `cycle-drive.py plain 30` y `track 25` (intro con degauss + quemado armado): 0 caídas en 55 ciclos.

## Osciloscopio con el audio real (tanda 7, corrida 7, evento `wave`)

- Fuente: tonos/ruido sintéticos (ffmpeg `aevalsrc` + `pw-play --volume=0.35`), Spotify en pausa. Evento
  `wave` = 64+64 enteros, ~730 bytes de JSON, 20 Hz (~15 KB/s por el socket).
- CPU A/B `scope-drive.py cpu` (`cpu-bench --scenario normal`, 5 muestras x 6 s, 4 condiciones intercaladas,
  2 rondas), % de un núcleo del overlay, media por condición: sin wave/silencio 33.0 y 54.6; wave fluyendo
  (Lissajous, CRT normal) 26.7 y 45.7; scope forzado CON wave 50.0 y 52.4; scope forzado SIN wave (sintético)
  50.3 y 46.5. Carga externa 1.8–2.6 (loadavg), pero el ruido entre rondas iguales es de ±10 puntos: la
  ronda 2 arrancó 20 puntos arriba en las 4 condiciones. Con el scope forzado, real vs sintético da
  +0.0/+5.9 puntos, dentro del ruido: el costo del parseo del evento (20 Hz, 128 enteros) y del trazo
  real no se distingue de cero con esta herramienta.
- Trampa de la medición: un overlay viejo (otro proceso `quickshell` del mismo repo) seguía vivo y pintaba
  NO SIGNAL encima del propio con el CRT prendido; hay que mirar `hyprctl layers | grep cartelitos-crt` y
  que haya UN solo pid antes de medir o capturar.

## Suciedad del audio (tanda 7, corrida 7b, campo `d` del evento `aud`, `crt.dirt`)

- Fuente: tonos/ruido sintéticos (ffmpeg + `pw-play --volume=0.35`), Spotify en pausa; no hubo música real
  para calibrar. `dirt-drive.py shots`: seno 220+330 -> d 0.00 (mult 1.00); seno+ruido -> 0.90 (2.79);
  ruido -> 0.75..1.00 (2.5..3.0); silencio -> baja a 0.02 (1.03) en ~4 s. Voz TTS limpia: mediana ~0.19.
- Costo del análisis en el hilo de audio (`spectral_flatness_local`, FFT de 512 puntos por bloque, stdlib
  puro): ~0.36 ms por bloque, ~1 % de un núcleo del daemon.
- CPU A/B del overlay (`dirt-drive.py cpu`: `cpu-bench normal`, 3 rondas intercaladas, `d`=0 contra `d`=0.8,
  5 muestras x 6 s, CRT prendido): d=0 media 32.7 % (rangos 28–36), d=0.8 media 34.7 % (29–40). Carga externa
  1.7–2.7 (loadavg). +2 puntos con rangos solapados y ruido de ±10 conocido de esta herramienta: no se
  distingue de cero (el multiplicador toca un uniform que ya se refresca por cuadro).

## Frío: `normal` y `pausa`, antes/después de la corrida 8 (tanda 7) + media resolución

- Aparejo SINTÉTICO (Spotify en pausa, no hubo música real): `cpu-bench normal` (aud 15 Hz + pos 1 Hz + un show cada
  4 s, sin forzar motivos ni foco) y `cpu-bench pausa` (un show y silencio). CRT prendido, 3 muestras x 8 s, % de un
  núcleo del overlay. Carga ajena de base ALTA en toda la medición (67–100 % de un núcleo: Hyprland ~19, Spotify ~17,
  pipewire ~10–15, a veces Vesktop ~22); se esperó 30 s y no bajó. "Antes" = `Crt.qml` de 437b715.
- `normal`: antes 32.7 % (28–36), después 32.9 % (30–35). Sin diferencia, esperado: el tope de 60 fps sólo frena el
  avance de `tubeTime` (la `FrameAnimation` sigue al refresco nativo) y `normal` no entra en reposo.
- `pausa` (con el daemon real bajado, ver TRAMPAS): antes 25.3 % (24–27), después 16.2 % (14–19). -9 puntos; entra a
  los ~5.3 s de cortar el audio en las 3 pantallas y sale a los 0.05 s del primer `pos`.
- Media resolución (`crtQuality` 1.0 / 0.85 / 0.75 / 0.6, `cpu-bench normal`, 3 x 8 s): 31.7 / 28.2 / 30.6 / 28.6 %.
  Diferencias de 1–3 puntos con rangos solapados y ±10 de ruido conocido: no se distingue de cero. Hoja de capturas
  (4 fuentes x 4 calidades, mismo verso, recorte 1:1): `docs/plans/tanda7/corrida-8-calidad.png` (no versionada).
  A ojo, a esa escala no se ve diferencia entre calidades.
- Las primeras pasadas de esta corrida (45 % / 35 %) salieron con el tubo APAGADO por la carrera de `restart` + `crt on`
  y se descartaron (TRAMPAS).

## Tanda 8 (2026-09-28): vidrio sin moiré, señales nuevas y reacción visual

- **Vidrio sin moiré** (`shell/crt.frag`, campo parejo sin ruido/viñeta, 1920×1080, `previews/shader-check/`):
  envolvente (contraste de las figuras falsas) y moiré (brillo 8–200 px) antes → después: custom 27.1 % → 0.15 %
  / 0.067 → 0.063; trinitron 11.4 → 0.12 % / 0.34 → 0.028; pvm 21.1 → 1.0 % / 0.77 → 0.25; arcade 25.3 → 0.20 % /
  1.38 → 1.14 (lo que queda es el puente de la slot mask, período 8 px, que ES su textura, no un batido);
  green/amber 32.4 → 0.6 % / 0.05 → 0.06. Brillo medio por canal sin cambio (±0.5 de 255). Suite: 691 tests OK.
- **Señales nuevas `cut`/`hf`** (`cartelitos/audio.py`, `AudioAnalyzer.feed`, `timeit` manual, 200 bloques de
  32 ms, bajo+medio+agudo variable, misma máquina): 0.641 ms/bloque antes → 0.662 ms/bloque después (+0.021 ms,
  ~3.3 % relativo, ~0.065 % de un núcleo extra sobre un hop de 32 ms). `hf` reusa la FFT que `dirt` ya calculaba
  (`power_spectrum`), no hay FFT nueva.
- **Reacción visual** (`shell/crt.frag` vía `shell/React.js`, banco offscreen `previews/reaccion/`, pace normal):
  corte — brillo medio durante el corte 1.003 → 0.479 del de antes, pico de vuelta 1.147 → 1.594. Golpe de bajo
  (a flicker 1): brillo +10.0 %, cambio local de rms 2.6, azul−rojo en claros −4.7. Agudos: brillo +0.08 %,
  cambio local de rms 3.8, azul−rojo en claros +25.9 (se distinguen del golpe de bajo). Grano (dirt 0.9,
  motivo arcade): contraste de franjas 0.067 → 0.32. CPU (render offscreen + grab, 300 cuadros, arcade):
  18.5 → 17.6 ms/cuadro, dentro del ruido — no medido en el overlay real. Suite: 718 tests OK.
- **Ritmo de los dibujos** (`shell/Speed.js`, banco offscreen `previews/movimiento/`, Mystify sin vidrio,
  1280×720, pace normal, rampa de `mov` 0→1→0 a los 240 s de tema): velocidad del reloj de dibujo integrada
  0.75–1.35 con desvío 0.0000 contra el `rate` del cuadro; control `t · rate` +63× a −63×. Cambio de imagen
  cuadro a cuadro (lum. media abs.): integrado 8.98 (máx 15.9), perilla en 0 9.05 (14.8), `t · rate` 12.2
  (23.3). CPU (render + grab, 600 cuadros, dos corridas): perilla en 0 5.38/5.44 ms/cuadro, ritmo andando
  5.48/5.45 — ruido. No medido en el overlay real.

## Distribución real de `mov` (tanda 8, movimiento-visual ronda 2, 2026-09-28)

`qs.log`+`.1` en vivo, Vivaldi/Invierno, 99 muestras (log cada 5 s): p1 0.63 · p5 0.64 · p25 0.67 ·
p50 0.73 · p75 0.76 · p95 0.78 · p99 0.80. Franja útil 0.17 de 0..1 → por eso el ritmo absoluto casi no
se notaba (rate 1.0–1.2); ahora se estira por percentiles del tema (`Speed.js`). Un solo tema
medido: recalibrar con otros géneros si hace falta.

- **Mystify: Shapes → un shader por píxel** (`previews/crt-motifs/bench.py`, banco offscreen con la placa real,
  1080p, sin vidrio, 3 rondas intercaladas, máquina con carga ~13 así que el ruido es ±0.5 ms; el suelo es
  `motifs/Floor.qml`, un `Item {}` que mide lo que cuesta el grab). Antes (`cf23e81`, 15 tandas de `MShape`,
  3×22 polilíneas rearmadas en JS por cuadro) → después (`mystify.frag`, cero geometría):

  | ms/cuadro | suelo | antes | después |
  |---|---|---|---|
  | lado QML (bindings+JS, sin dibujar) | 0.21 | 0.75 | **0.22** (= suelo) |
  | pared con grab | 1.5–1.6 | 2.2–3.0 | 1.8–2.0 |
  | CPU del proceso con grab | 2.7 | 3.7–4.2 | 3.3–3.5 |

  Neto sobre el suelo: pared ~1.0–1.4 → ~0.2–0.5 ms; lado QML ~0.55 → ~0. En el mismo banco
  (sin vidrio, una corrida) **Mystify NO era el más caro**: swarm 14.9, defrag 7.8, pipes 7.0, vector 4.3,
  splitflap/harmonograph/mystify 3.1, maze 1.9 (con vidrio: swarm 12.2, defrag 9.8, pipes 6.7, mystify 6.1
  —el tubo `arcade`, más caro— vector 4.8, harmonograph 3.6, splitflap 3.3, maze 2.1). Los números en vivo del
  README (24–28 % mystify contra 65 % swarm/defrag) dicen lo mismo. La causa del costo viejo no era un Canvas
  (ya era Shape) sino tessellar 66 polilíneas de trazo ancho con MSAA 4× en CPU cada cuadro. Ojo: la CPU del
  banco incluye la espera de la placa en el grab; el costo real del overlay es menor en ambos.

## `mov` ronda 3: "se ve el cambio pero es mínimo" (tanda 8, 2026-09-28)

Pedido de Ferox con música real: más notorio, más sensible al ritmo. **Aviso de método:** el daemon
NO se reinició (Fatal Lyrics prendido), así que la distribución de `qs.log` en vivo de la ronda 2 no se
pudo repetir con el `mov` nuevo. Se usó como proxy una réplica offline: captura real de 98 s (Home / X,
`parec` → `AudioAnalyzer.feed` con el código nuevo → 800 eventos `aud`) → el `Speed.js` real en node
(`observe` a 10 Hz, como el overlay). Un tema, un género: recalibrar con otros.

- **Qué estaba mal en la señal:** el término de densidad de onsets estaba saturado
  (`MOV_ATTACK_THRESH` 0.12 contaba como onset el ruido de una textura densa y el término se pegaba a 1) y
  la cadena era lenta: suavizado 1.0 s sube / 3.0 s baja + Behavior de 420 ms en `crtMovRate` + estirado
  lineal por p5..p95. Ahora: umbral 0.45, densidad compresiva `1 − exp(−n/REF)` (no un tope duro), término
  nuevo de densidad de golpes (`MOV_W_BEAT`, ventana 1.5 s), pesos 0.35/0.20/0.25/0.20
  (onsets/golpes/brillo/energía), suavizado **0.25 s sube / 0.7 s baja**.
- **`mov` en la captura (Home / X):** música con pulso, 28–68 s, entre 0.56 y 0.71 (mediana 0.63); un final
  que se calma desde 68 s (0.2–0.4) y silencio. Con la señal vieja (umbral 0.12) el pasaje con pulso quedaba
  pegado arriba, sin margen. `mov` cae de 0.62 a 0.40 en el primer segundo de la calma y a ≤ 0.3 a los 4 s.
- **Curva** (mismos eventos, `Speed.js` viejo vs nuevo, pace normal 0.4–2.2; ritmo por cuadro de `aud`):

  | ventana | mapeo | p5 | p25 | p50 | p75 | p95 | cerca de movMin | cerca de movMax |
  |---|---|---|---|---|---|---|---|---|
  | música 30–68 s | p5..p95 lineal | 1.55 | 1.79 | 1.94 | 2.09 | 2.20 | 1 % | 54 % |
  | música 30–68 s | cuantiles 10/50/90 | 0.90 | 1.10 | 1.48 | 1.73 | 2.06 | 1 % | 11 % |
  | todo 26–80 s | p5..p95 lineal | 0.40 | 0.94 | 1.84 | 2.01 | 2.19 | 17 % | 39 % |
  | todo 26–80 s | cuantiles 10/50/90 | 0.40 | 0.78 | 1.19 | 1.62 | 2.03 | 25 % | 8 % |

  ("cerca" = a menos de 15 % del rango de un extremo.) El estirado lineal p5..p95 con el pivote en el punto
  medio de la franja sesgada dejaba el tema pegado al máximo (54 % del pasaje con pulso en ×2.2: NO se
  distinguía un compás del siguiente); con la mediana en ritmo 1 el pasaje habitual se reparte entre ×0.9 y
  ×2.06 y la calma toca `movMin` (0.4). Un `x^p` con p < 1 se descartó (pendiente infinita en el pivote:
  amplifica justo el ruido donde `mov` pasa más tiempo); el smoothstep sobre la franja también (empujaba de
  nuevo a los extremos sin corregir el sesgo).
- **Latencia de la respuesta** (banco `previews/movimiento/render.py sheet --score fast`, partitura de `mov`
  con el suavizado nuevo, ritmo BASE sin golpes): sube al 90 % del pasaje nervioso en **0.33 s** y baja al
  90 % del calmo en **0.78 s** (antes ~1 s / ~3 s + 0.42 s de Behavior). En la captura, la calma del final
  lleva el ritmo a `movMin` en ~1.3 s.
- **Empujón del golpe** (`Speed.kickAt/kickAdd/push`, `movKick` por fila: calm 0.4 / normal 0.7 / wild 1.0):
  golpe común pesa 0.4, fuerte (`h`) 1.0, tope 1.5 · `movKick` si se encima; decae en 0.42 s (OutQuad,
  `Speed.KICK_S`). Multiplica el ritmo base: pace normal, base ×1.59 (nervioso) → ×2.70 con un golpe fuerte,
  y vuelve. Banco (721 cuadros a 60 fps, T0 = 240 s): velocidad del reloj de dibujo integrada 0.60–2.70,
  **desvío máximo contra el `rate` del cuadro 0.0000**, perilla en 0 = 1.0 exacto; el control `t · rate`
  llega a +16381× / −1272×. Partitura lenta (rampas de 4 s, sin golpes): integrado 0.40–2.20, desvío 0.0000,
  control ±200×. Cambio de imagen cuadro a cuadro (lum. media abs.): integrado 8.22 (máx 15.9), perilla en 0
  9.05 (14.8), control 11.7 (22.4). Sin muestrear CPU de nuevo: lo agregado en el overlay es un
  `FrameAnimation` que sólo corre 0.42 s después de cada golpe y dos multiplicaciones por cuadro.
- **No hecho:** tempo local. `BpmTracker` está armado para golpes tipo bombo (histograma de intervalos entre
  `beat`); en un pasaje de cuerdas rápidas no da. La densidad de onsets + la de golpes (últimos 0.6 / 1.5 s)
  cubre lo que se pidió sin un estimador nuevo.
