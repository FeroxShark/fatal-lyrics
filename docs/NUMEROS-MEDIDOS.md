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
  8.2–8.3 %; piso de ruido (0 vs 0 bis) < 0.65 %. Techo pedido: 5 % / 10 %.
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
