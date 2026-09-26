# cartelitos / fatal-lyrics

## Qué es y para qué

Las letras sincronizadas de lo que suena en Spotify, tiradas en pantalla como **diálogos de error
de Win95**. Tiene un segundo modo, el **CRT**, donde cada monitor se vuelve un tubo de rayos
catódicos con la letra adentro.

Repo **público**: `https://github.com/FeroxShark/fatal-lyrics`. El binario de sistema es
`~/.local/bin/cartelitos` (symlink acá). El launcher es relocatable, con `qs -p`.

## Cómo pensarlo

- **Dos procesos, no uno.** Un daemon de Python (busca la letra, la sincroniza, la manda) y un
  overlay de Quickshell (la dibuja). Se hablan por un socket Unix. Cualquier diagnóstico tiene que
  mirar **los dos PIDs**: `fatal status` distingue ON / HALF / OFF justamente porque el daemon
  vivo con el overlay muerto es un estado real y frecuente.
- **La config es un TOML con hot-reload**, no un wizard. `~/.config/cartelitos/config.toml` viaja
  del daemon al overlay por el socket; el daemon vigila el mtime y aplica en vivo. Nada necesita
  `fatal restart`. Un TOML roto conserva la config anterior.
  `fatal config` es un menú de UNA pantalla: se tipea el número de lo que se quiere cambiar y se
  vuelve al menú (`u` deshace, `d` demo, `q` sale). **No volver al wizard lineal** — con 24
  preguntas seguidas, equivocarse obligaba a empezar de cero.
- **El interruptor del CRT es un ARCHIVO**, no el socket: `$XDG_RUNTIME_DIR/cartelitos-crt`, que
  el QML vigila. Así apaga aunque el daemon esté colgado.
- **El tubo sabe dónde va a caer la línea SIGUIENTE.** El daemon manda una línea por vez, así que
  el `show` viaja con `next` (`{text, t0, t1, segs}`, o `null`) y hay un evento `lyrics` con la
  letra entera del tema. Con eso el overlay calcula el reparto de la línea k+1 mientras suena la k
  y lo **consume** cuando llega: la anticipación es la verdad, no un pronóstico. De ahí salen el
  motif que huye (`foreshadow`) y el aro que cuenta (`ring`, `shell/Ring.qml`). Con el `next`
  viaja también el `due` — cuándo va a salir el próximo `show`, con el offset del daemon ya
  descontado — y con el `show`, el `v_end` de la línea que suena.
- **El salto de la frase se ve viajar, y ESA es la flecha.** Cuando la línea cae en otra pantalla,
  la perilla `hop` (`corridor|interference|both|off`) manda un rayo: nace como hebras estiradas de
  la letra que se va, cruza cada pantalla del medio POR EL BORDE (arriba o abajo, alternando) y
  converge al centro de la de destino, encima de la línea que llega. Cabeza brillante y cola, y
  el color va del de la letra de origen al de la de destino a lo largo de todo el viaje. El reloj
  (360 ms + 150 de cola; 200 + 150 si es a la pantalla de al lado, que es la mitad de camino a la
  misma velocidad) lo publica `shell.qml` UNA vez (`crtHopStart`) y cada monitor lo lee: es un
  solo rayo atravesando la pared. **El rayo es lo que dice DÓNDE va a caer la letra** — textual
  de Ferox: "me gusta la línea glitchada que indica 'tu ojo va a ir para acá', esa antes que un
  timer" —, y por eso sale también en el salto de una sola pantalla (tanda 4). El aro no señala
  nada: avisa que vuelve la voz.
- **REGLA: una animación por pantalla.** Textual de Ferox: "no quiero que ninguna animación se
  superponga con ninguna". En cada pantalla hay UNA cosa a la vez — o el motivo, o el aro, o la
  letra con su entrada, o el instrumental. Por eso el aro apaga el motivo de su pantalla (`dim` a
  0 en 220 ms) en vez de contar encima de él. La única excepción es el rayo del salto, y sólo
  porque va por el BORDE de la pantalla del medio: no pasa por encima de nada.
- **REGLA: hay UN lenguaje de movimiento, y vive en `shell/Motion.qml`.** Todo lo que entra
  entra igual — snap `OutExpo` con asentamiento visible (`enterMs`, 320 ms; `enterFastMs` para
  lo que entra encima de algo que ya está pasando) —, todo lo que se va se va rápido (`exitMs`,
  140, `InQuad`), la cámara se mueve una vez y se queda quieta (`cameraMs`), y el glitch es un
  PUENTE de dos o tres cuadros entre escena y escena (`bridgeMs`), nunca un efecto que dura. Un
  `Behavior` que quiera otra duración tiene que justificar por qué su movimiento no es ninguno
  de ésos. Sale del video que pasó Ferox
  (`docs/plans/2026-09-04-fluidez-referencia.md`): lo fluido no son más cuadros: es una sola
  gramática, holds largos entre eventos y una deriva uniforme por debajo que nunca para.
- **REGLA: los eventos tienen PRESUPUESTO, y es la perilla `pace`** (`calm | normal | wild`,
  default `normal`, tabla `crtPaceTable` en `shell.qml`). No es una velocidad: nada se mueve más
  despacio. Es cuántas cosas tienen permiso de pasar por minuto — cuánto dura el dibujo de una
  pantalla antes de poder cambiar (12 s), cada cuánto la pared puede cambiar de canal (20 s),
  cada cuánto una pantalla puede romperse (4 s), y qué tan grande es el latido de la cámara y
  del motivo. `wild` devuelve exactamente los números de la tanda 3. Un número de amplitud o de
  frecuencia nuevo va a la TABLA: repartido en ternarios por los archivos, `wild` deja de ser
  verificable.
- **Una pantalla sin letra no dibuja cualquier cosa: dibuja algo del tema.** Los motivos leen lo
  que el tubo ya sabe (la letra que viene, el ritmo, el drop, el compás). `dunes` es el único paisaje:
  quieto, la cámara se mueve. `eyes` es UN ojo mirando a la pantalla que tiene la frase. Qué lee cada
  uno: `docs/TRAMPAS.md` ("Detalle movido: motivos y set").
- **Cómo entra la línea lo decide la música, no un sorteo parejo.** `crtEntriesFor` reparte UN
  estilo de entrada por pantalla al consumir la línea, pesado por el nivel de los últimos ~2 s y
  por la parte del tema (tabla `crtEntryTable` en `shell.qml`, con el comentario de cómo tunearla).
  Se sumaron `interlace` (medio cuadro, uniform del shader), `tubeon` (punto → raya → imagen, el
  apagado al revés) y `overburn` (cada palabra quemada en blanco, sólo en un drop con compás
  confiable). La cámara además sigue la sección (`section_zoom`): lejos en la estrofa, encima en el
  drop.
- **El sync a ojo aprende por TEMA antes que por artista.** `fatal sync +/-` corrige el
  tema que suena de una; el offset se le guarda al ARTISTA recién cuando dos temas distintos
  suyos pidieron lo mismo (`offsets.record(artist, delta, track_id)`). Lo que se guarda es el
  PROMEDIO de los que votaron, no la suma, y a los que votaron se les descuenta (rebase), así
  el tema que suena no pega un salto en el mismo golpe que persistió. Se mira y se borra con
  `fatal sync show` / `fatal sync reset [<artista>|all]`, que no necesitan el daemon.
- **En el CRT la letra no se clona.** Hay una pantalla enfocada, la frase sigue en la de al lado y
  el pedazo ya leído queda quemado abajo. Las repeticiones se cortan en el daemon
  (`split_repeats`) y cada golpe cae en otra pantalla. `focus = "all"` vuelve al comportamiento
  viejo.
- **La letra va en el idioma en que se canta.** Cadena de proveedores (`lrclib` exacto →
  `lrclib` búsqueda → `NetEase`), título original y después el limpio, gana el primer `ok`.
  De NetEase `lrc`, **nunca** `tlyric` (traducción al chino). Ningún campo de traducción.
- **Casi todo lo raro tiene una razón medida.** Los gotchas caros están documentados EN EL CÓDIGO.
  Leerlos antes de "optimizar" algo que parece raro.

## Mapa

- `bin/fatal` — CLI: `on|off|restart|status|config|demo|crt on|off|toggle|sing on|off`,
  `crt motif <kind> [--screen <nombre|idx|all>]|off` y `sync +|-|show|reset [<artista>|all]`
  (`sync show|reset` y `crt motif` NO necesitan el daemon; `crt motif` habla con el overlay).
- `shell/shell.qml` — reparte qué dibuja cada pantalla.
- `shell/Crt.qml` — el tubo, en DOS pasadas (tanda 7): `stage` → `signal.frag` (la señal: compuesta,
  perilla `crt.composite`) → `crt.frag` (el vidrio: fósforo, scanlines, rotura). Un `.qsb` c/u.
  `crtTubeTable` (`shell.qml`, perilla `crt.tube`, corrida 2): cada tubo es una fila con las perillas
  sueltas + `maskType`/`maskPitch`/`mono`/`monoTint` (uniforms de `crt.frag`); `custom` = look de
  siempre y es el único que obedece las sueltas. `auto` (en `crtSetFor`) sortea sólo tubos de color.
  **Estela** (corrida 3, `crt.persistence`): `signalTex` es `recursive`, `signal.frag` guarda
  `max(señal, prev*decay - piso)`; `trailOn` exige `trailQ` (= `crtQuality >= 1` con 150 ms de retraso: el
  resize y `recursive` nunca cambian en el mismo cuadro, TRAMPAS), el `dt` sale de `frameSwapped`
  (`docs/TRAMPAS.md`). Vida media = persistence × 220 ms.
- `crtTension`/`crtClimaxT` (`shell.qml`, `crt.tension`, corrida 4a) — `rep` `{n,k,chorus}`
  (`lyrics.repeat_map`) viaja en `lyrics.lines[i]`, `show` y `next`. La tensión sube con `posAbs`
  hasta `crtClimaxT` (última ocurrencia de la línea más repetida), un escalón mientras suena un
  `chorus`, baja en el outro. Multiplica UN camino: `rest` de `Crt.qml` y `hitGap`; rango
  `tensionMin/Max` en `crtPaceTable`. Driver: `docs/plans/chorus-drive.py`.
- `shell/Motif.qml` — dieciséis animaciones para las pantallas sin letra: reparte propiedades y
  elige cuál dibuja. Las dieciséis son un `Component` cada una y las pone **UN solo `Loader`**
  (`sourceComponent` según `kind`): dos motivos no pueden estar vivos a la vez. Las que tienen
  física propia viven al lado, un archivo cada una — `Ocean.qml`, `Pond.qml`, `Dunes.qml`,
  `Static.qml`, `Rorschach.qml`, `Plasma.qml` y `Tunnel.qml` (con su `.frag` + `.qsb`), más
  `Ekg.qml` (Canvas), `TextSea.qml`, `Eyes.qml` y `Eye.qml` (el dibujo del ojo, que usan el
  motivo `eye` y la grilla `eyes`). Lo que se dibuja con items sueltos (el radar, la lluvia, el
  hiperespacio, la carta de ajuste, el osciloscopio) sigue adentro de `Motif.qml`. El osciloscopio
  dibuja el audio REAL (tanda 7, corrida 7): ver `wave` abajo.
- `motifKinds` + `motifWords` + `motifAllowed` (`shell.qml`) — la lista, las palabras de la letra
  que eligen uno a propósito, y el filtro de los que ahora mismo no tienen con qué dibujarse.
- `cartelitos/motifs.py` + `crtSetForceMotif` / `crtMotifForced` (`shell.qml`) — el forzado de
  `fatal crt motif`: el parseo y el socket de un lado, el evento `motif` y el pisado del sorteo
  del otro. La lista de kinds del `--help` se LEE de `motifKinds` en `shell.qml`, no se copia.
- `crtDark[]` / `crtSetDark(i, on)` / `tubeDark` (`Crt.qml`) — el tubo apagado: `fatal crt dark
  <screen|all> on|off` lo prende/apaga por socket, y `crtPredict()` lo reenciende solo antes de
  que llegue la letra ("la letra prende el tubo").
- `crtSceneFor(section, outro, n, focus)` + `crtSceneApply`/`crtSceneStartOutro`/
  `crtSceneOutroCheck` (`shell.qml`, perilla `crt.scene = sections | all`, tanda 6, corrida 4) —
  la sección decide qué pantallas viven sobre el primitivo `crtSetDark` de la corrida 0: la
  estrofa deja una sola pantalla prendida (la del foco), el drop enciende la pared entera
  (portero `sceneGapMs` de `crtPaceTable` salteado a propósito, siempre pasa) y el final del
  tema (umbral de `posAbs/posLen`, no lo manda el daemon) apaga de a una hacia el foco, una
  cada `Motion.holdMs`, con un timer único reapuntado (mismo patrón que `crtRelightTimer`).
  Nunca apaga la pantalla que `crtPredict()` ya prendió por anticipación.
- `crtIntroPhase`/`crtIntroScreen` + `crtIntroStart`/`crtIntroAdvance`/`crtIntroEnd`/
  `crtIntroSkip` (`shell.qml`, perilla `crt.intro`, tanda 6, corrida 5; v2 tanda 7, corrida 6:
  `crt.intro_card`) — el cambio de tema es un evento: `clear` (why="track") apaga la pared,
  degauss (uniform de `crt.frag`), estática (`Static.qml`) y la tarjeta (carta de ajuste
  `testcard` con título/artista) en la pantalla del próximo foco. La tarjeta NO tiene plazo: la
  corta `show()`. Detalle del orden y los cortes en `docs/TRAMPAS.md` ("Detalle movido").
- `shell/WordSlot.qml` + `crt.wholeWordsOn` (`Crt.qml`, tanda 6, corrida 6) — la palabra que
  suena pulsa con la familia de entrada del set (`crt: word <i> <emphasis>`). `wholeWordsOn`
  gatea el `Flow` por palabra (4.4 puntos de CPU); el auto-drop de calidad lo apaga.
- `crtRareKinds` + `crtRare`/`crtRareTimer`/`crtRareRoll`/`crtForceRare` (`shell.qml`, perilla
  `crt.rare`, tanda 6, corrida 7) — eventos raros `bsod`, `nosignal` y `testcard`; el sorteo
  nunca cae en intro ni en pantalla oscura. `fatal crt rare <kind> [--screen ...]` fuerza uno.
- `burn.frag` + `burnLoader` (`Crt.qml`, perilla `crt.burnin`, tanda 7, corrida 4b) — quemado del
  estribillo: desde la 2da ocurrencia (`rep.chorus`, k>=2) la silueta de la línea queda tenue en su
  pantalla hasta el `clear why=track`. Es ESTADO: `burnTex` recursivo, no vivo, se redibuja
  sólo en `burnSnap()` (640 ms después de asentar); `signal.frag` lo suma bajo la señal. Techo de
  contraste 0.10×burnin. Fade en el outro por cuenta sobre `posAbs` (`crtBurnFade`), nunca un
  Behavior. Los items viven en un Loader (ver TRAMPAS).
- `hit()` + `rollPhase` (`Crt.qml`, `crt.beat_lock`, tanda 7, corrida 5a) — con `bpmLive`, el glitch sin
  animación propia (`line`, `interf`) espera al próximo tiempo, máx uno (`beatStep`; log `beat+<ms>`);
  aro, salto, tubeon, canal y cámara son `urgent`. Barra: N compases (`rollPhaseFor`).
- `motifWords` `{re, kind?, fx?}` + `fxCheck`/`fxFire` (`Crt.qml`, `crt.word_fx`, tanda 7, corrida 5b) — fuego/
  morir/romper/oscuro pegan al tubo de la pantalla con la palabra, 1 vez por línea, vía `hit()` y `fxGapMs`.
  Trampas: `docs/TRAMPAS.md`.
- `shell/Ring.qml` — el cronómetro de la línea que viene: arco que se vacía en sentido horario,
  doce marcas, número en el centro y colapso que empalma con la entrada de la frase.
- `shell/Motion.qml` — singleton con las constantes de movimiento del tubo (`enterMs`,
  `enterFastMs`, `exitMs`, `cameraMs`, `dimMs`, `levelMs`, `holdMs`, `bridgeMs`). Las usan el
  aro, las entradas del verso, el puente entre dibujos, el rayo del salto y los nueve motivos.
- `crtPaceTable` + `pace` (`shell.qml`) — el presupuesto de eventos de la perilla `pace`, en
  una tabla sola. `crtMotifKinds` / `crtMotifSince` / `crtMotifSeeds` + `crtMotifRefresh()` —
  qué dibuja cada pantalla, desde cuándo y con qué semilla.
- `shell/HopRay.qml` — el rayo del salto: el recorrido, la cabeza, la cola y el degradado.
- `crtEntryTable` + `crtPickEntry` (`shell.qml`) — los pesos de las entradas y el sorteo.
- `crtSetFor(seed, mood)` (`shell.qml`) — el set por tema (perilla `crt.set`, tanda 6): 4 kinds
  de motif, familia de entrada (`crtEntryFamilies`), scheme y fuente, de una semilla atada a
  `crtTrackSeed`. `crtMotifBag`/`crtEntryBag`: mazos barajados con `crtHash`, sin repetir hasta
  agotarse. `crt.set = "off"` vuelve al sorteo plano. El `mood` (corrida 3) se congela una vez por
  tema (`crtMoodLocked`). Detalle: `docs/TRAMPAS.md` ("Detalle movido: motivos y set").
- `cartelitos/mood.py` — `mood_for(lines, profile_summary, bpm)`: valence/energy/bright
  determinísticos (léxico chico es/en para valence, rms absoluto calibrado contra `~/.cache/
  cartelitos/audio` para energy, sin red ni IA — `feedback_ia_sin_creditos`). El daemon lo manda
  por el socket como evento `mood`, hasta dos veces por tema (al juntar la letra, y de nuevo si
  el compás se asienta después).
- `cartelitos/lyrics.py` — cadena de proveedores, cache, LRC "enhanced" (tiempo por
  palabra) y `split_repeats`.
- `cartelitos/offsets.py` — corrección de sync por artista (`offsets.toml`), separada de
  `config.py` porque la escribe el propio daemon, no Ferox a mano. Adentro vive también el
  perfil por tema (`_pending`, en memoria): lo que todavía no se ganó el derecho a durar.
- `[keys] sync_forward` / `sync_back` (`config.py`) + `system.key_bind_commands()` — las
  teclas del sync. NO viajan al overlay: las aplica Hyprland desde el daemon.
- `packaging/PKGBUILD` + `.SRCINFO` — listos, build probado con makepkg.
- `audio.downmix_stereo` + `wave_points` + evento `wave {l,r}` (`audio.py`/`Motif.qml`, tanda 7, corrida 7) —
  la captura es estéreo pero se baja a mono `(L+R)>>1` ANTES de `AudioAnalyzer.feed` (test: idéntico al mono
  de antes; no descalibra perfiles ni `ENERGY_GAIN_REF`; la 7b reusa `downmix_stereo`). A `WAVE_HZ`=20
  van 64+64 enteros por `send_soft`; el scope hace Lissajous L/R, retrato de fase si |corr|>0.98 y vuelve al
  sintético sin `wave` >300 ms (`waveStaleMs`). Driver: `docs/plans/scope-drive.py`.
- `audio.dirt_from` + `AudioAnalyzer._smooth_dirt` + campo `d` de `aud` → `crtDirt`/`crtDirtMult` (`crt.dirt`, tanda 7,
  corrida 7b) — planitud espectral local (ruido/guitarras) escala SÓLO `noiseAmt` (rango `dirtMin/Max` de `crtPaceTable`).
  Guardia de instancia única: `flock` en daemon (`util.acquire_instance_lock`) y overlay (`spawn` de `bin/fatal`).
- `tests/` — 678 tests, stdlib puro.

Cachés: `~/.cache/cartelitos/lyrics/` (letras) y `~/.cache/cartelitos/audio` (mapa de energía por
tema).

## Cómo correrlo / testearlo

```bash
fatal on | off | restart | status
fatal demo                 # SIGUSR1: carteles falsos, sin música
fatal crt toggle           # también Super+Shift+Y
fatal sync + | -           # ajuste fino ±0.1s, también Super+Alt+Right/Left o el menú de bandeja
python3 -m unittest discover -s tests
```

### Para VER un motif

```bash
fatal crt motif dunes --screen DP-4    # esa pantalla, ese dibujo, ya
fatal crt motif tunnel --screen all    # toda la pared (rompe la unicidad a propósito)
fatal crt motif off                    # vuelve el sorteo normal
docs/plans/motif-force.py dunes DP-4 10 --shot t4-dunes   # + captura, y deja todo como estaba
```

**NUNCA pescar un motif con palabras clave ni rerollear con `cue drop`.** Así se hacía hasta la
tanda 4 (`drive-motif.py`, `motif-hunt.py`, hoy OBSOLETOS) y era esperar minutos a que el sorteo
sacara el dibujo que se quería mirar. El forzado pisa el pool, el hold, el filtro de validez y la
palabra clave, y se ve aunque no suene nada. La letra sigue dibujándose encima: sirve para mirar
un motivo CON el verso puesto. Los kinds válidos los lista `fatal crt motif --help` (salen de
`motifKinds` en `shell.qml`, no de una copia).

Autostart: **UNO solo** `exec-once` en `execs.conf` con `sleep 6 && cartelitos restart`. `restart`
deja estado limpio aunque haya quedado media instancia. No reintroducir un segundo (`docs/TRAMPAS.md`).

## Dónde está el resto (leer sólo lo que toca)

**Tope de este archivo: 20.000 caracteres.** Es el mapa mental + índice.

- `docs/TRAMPAS.md` — Bugs que ya pasaron y por qué. Antes de diagnosticar algo raro, buscá acá. Cada trampa nueva va acá, no a `CLAUDE.md`.
- `docs/NUMEROS-MEDIDOS.md` — Mediciones de CPU/latencia y cómo se tomaron. Los números nuevos van acá.
- `docs/PENDIENTES.md` — Backlog vivo. Leerlo al planear una tanda.
- `docs/plans/` — planes y feedback por tanda.

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
