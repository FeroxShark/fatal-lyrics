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
  converge al centro de la de destino, encima de la línea que llega. Cabeza brillante y cola, color
  degradado origen→destino. Un solo reloj lo publica (`shell.qml`, `crtHopStart`) y cada monitor lo
  lee. **El rayo es lo que dice DÓNDE va a caer la letra** — textual de Ferox: "me gusta la línea
  glitchada que indica 'tu ojo va a ir para acá', esa antes que un timer". El aro no señala nada:
  avisa que vuelve la voz.
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
- `shell/Crt.qml` — el tubo, en DOS pasadas: `signal.frag` (la señal, perilla `crt.composite`) →
  `crt.frag` (el vidrio: fósforo, scanlines, rotura, estela). `crtTubeTable` (`shell.qml`, perilla
  `crt.tube`) define el tubo por tema; default `auto` (`crtSetFor`), `custom` = look de siempre.
  Detalle de las dos pasadas y la estela: `docs/TRAMPAS.md` ("Detalle movido: mapa técnico").
- `crtTension`/`crtClimaxT` (`shell.qml`, `crt.tension`) — la tensión sube con la repetición de la
  letra (`rep`, `lyrics.repeat_map`) hasta el estribillo más repetido, y multiplica el ritmo del
  tubo (`rest` de `Crt.qml`, `hitGap`). Detalle: `docs/TRAMPAS.md` ("Detalle movido: mapa técnico").
- `shell/Motif.qml` — animaciones para las pantallas sin letra: reparte propiedades y elige cuál
  dibuja con **UN solo `Loader`** (dos motivos no pueden estar vivos a la vez). Física propia en
  archivos aparte: `Ocean.qml`, `Pond.qml`, `Dunes.qml`, `Static.qml`, `Rorschach.qml`,
  `Plasma.qml`, `Tunnel.qml`, `Ekg.qml`, `TextSea.qml`, `Eyes.qml`/`Eye.qml`. El resto (radar,
  lluvia, hiperespacio, carta de ajuste, osciloscopio) vive adentro de `Motif.qml`.
- `motifKinds` + `motifWords` + `motifAllowed` (`shell.qml`) — la lista, las palabras de la letra
  que eligen uno a propósito, y el filtro de los que ahora mismo no tienen con qué dibujarse.
- `cartelitos/motifs.py` + `crtSetForceMotif`/`crtMotifForced` (`shell.qml`) — el forzado de
  `fatal crt motif` (parseo+socket de un lado, evento `motif` del otro). El `--help` LEE
  `motifKinds` de `shell.qml`, no lo copia.
- `crtDark[]` / `crtSetDark(i, on)` / `tubeDark` (`Crt.qml`) — el tubo apagado: `fatal crt dark
  <screen|all> on|off` lo prende/apaga por socket, y `crtPredict()` lo reenciende solo antes de
  que llegue la letra ("la letra prende el tubo").
- `crtSceneFor(section, outro, n, focus)` + `crtSceneApply`/`crtSceneStartOutro`/
  `crtSceneOutroCheck` (`shell.qml`, perilla `crt.scene = sections | all`) — la sección decide qué
  pantallas viven: la estrofa deja sólo el foco prendido, el drop enciende la pared entera y el
  final del tema apaga de a una hacia el foco. Nunca apaga la pantalla que `crtPredict()` ya
  prendió por anticipación. Detalle: `docs/TRAMPAS.md` ("Detalle movido: mapa técnico").
- `crtIntroPhase`/`crtIntroScreen` + `crtIntroStart`/`Advance`/`End`/`Skip` (`shell.qml`,
  perilla `crt.intro`, `crt.intro_card`) — el cambio de tema es un evento: `clear` (why="track")
  apaga la pared, degauss, estática y la tarjeta (título/artista) en la pantalla del próximo foco,
  sin plazo: la corta `show()`. Detalle: `docs/TRAMPAS.md` ("Detalle movido desde CLAUDE.md").
- `shell/WordSlot.qml` + `crt.wholeWordsOn` (`Crt.qml`) — la palabra que suena pulsa con la familia
  de entrada del set. Costo y auto-drop de calidad: `docs/TRAMPAS.md` / `docs/NUMEROS-MEDIDOS.md`.
- `crtRareKinds` + `crtRare`/`crtRareTimer`/`crtRareRoll`/`crtForceRare` (`shell.qml`, perilla
  `crt.rare`) — eventos raros `bsod`, `nosignal` y `testcard`; el sorteo nunca cae en intro ni en
  pantalla oscura. `fatal crt rare <kind> [--screen ...]` fuerza uno.
- `burn.frag` + `burnLoader` (`Crt.qml`, `crt.burnin`) — quemado del estribillo: desde la 2da
  ocurrencia del chorus queda tenue, se desvanece sin chorus y se limpia al cambiar de tema.
  Detalle y crashes evitados: `docs/TRAMPAS.md` ("El quemado del estribillo").
- `hit()` + `rollPhase` (`Crt.qml`, `crt.beat_lock`) — con `bpmLive`, el glitch sin animación
  propia espera al próximo tiempo (máx uno); aro, salto, tubeon, canal y cámara son `urgent`.
  Detalle: `docs/TRAMPAS.md` ("Glitches en el tiempo").
- `motifWords` `{re, kind?, fx?}` + `fxCheck`/`fxFire` (`Crt.qml`, `crt.word_fx`) — fuego/morir/
  romper/oscuro pegan al tubo de la pantalla con la palabra, 1 vez por línea. Detalle:
  `docs/TRAMPAS.md` ("Efectos por palabra").
- `shell/Ring.qml` — el cronómetro de la línea que viene: arco que se vacía en sentido horario,
  doce marcas, número en el centro y colapso que empalma con la entrada de la frase.
- `shell/Motion.qml` — singleton con las constantes de movimiento del tubo (`enterMs`,
  `enterFastMs`, `exitMs`, `cameraMs`, `dimMs`, `levelMs`, `holdMs`, `bridgeMs`). Las usan el
  aro, las entradas del verso, el puente entre dibujos, el rayo del salto y los nueve motivos.
- `crtPaceTable` + `pace` (`shell.qml`) — el presupuesto de eventos de la perilla `pace`, en
  una tabla sola. `crtMotifKinds` / `crtMotifSince` / `crtMotifSeeds` + `crtMotifRefresh()` —
  qué dibuja cada pantalla, desde cuándo y con qué semilla.
- `shell/Speed.js` + `crtMovRate`/`movOff` (`crt.mov_speed`, `movMin`/`movMax` en `crtPaceTable`) — la
  deriva de los motivos sigue `mov` del `aud`, INTEGRADA (nunca `t·rate`); entradas, shader y compás no.
  TRAMPAS: "El ritmo de los dibujos". Banco: `previews/movimiento/`.
- `shell/HopRay.qml` — el rayo del salto: el recorrido, la cabeza, la cola y el degradado.
- `crtEntryTable` + `crtPickEntry` (`shell.qml`) — los pesos de las entradas y el sorteo.
- `crtSetFor(seed, mood)` (`shell.qml`, perilla `crt.set`) — el set por tema: familia de entrada,
  scheme y fuente, de una semilla atada a `crtTrackSeed`. Los DIBUJOS no salen del set:
  `crtMotifDraw` sortea con dados cargados por lo que suena. `crt.set = "off"` vuelve al sorteo
  plano. Detalle: `docs/TRAMPAS.md` ("Detalle movido: motivos y set").
- `crtFontPools` (`shell.qml`) — mazo de fuentes por familia de entrada, elegido con el mismo dado
  que la fuente del set (sin Press Start 2P, no le gustaba): plex, space, chakra, syne, vt323,
  share, system — créditos: `shell/fonts/README.md`.
- `shell/Faces.js` + `crt.face_mode` — tres caras por paleta, la sección las reparte. TRAMPAS: "Tres caras".
- `cartelitos/mood.py` — `mood_for(lines, profile_summary, bpm)`: valence/energy/bright/contrast
  determinísticos, sin red ni IA (`feedback_ia_sin_creditos`). El daemon lo manda por el socket
  como evento `mood`, hasta dos veces por tema. Detalle: `docs/TRAMPAS.md` ("Detalle movido: mapa técnico").
- `cartelitos/lyrics.py` — cadena de proveedores, cache, LRC "enhanced" (tiempo por
  palabra) y `split_repeats`.
- `cartelitos/offsets.py` — corrección de sync por artista (`offsets.toml`), separada de
  `config.py` porque la escribe el propio daemon, no Ferox a mano. Adentro vive también el
  perfil por tema (`_pending`, en memoria): lo que todavía no se ganó el derecho a durar.
- `[keys] sync_forward` / `sync_back` (`config.py`) + `system.key_bind_commands()` — las
  teclas del sync. NO viajan al overlay: las aplica Hyprland desde el daemon.
- `packaging/PKGBUILD` + `.SRCINFO` — listos, build probado con makepkg.
- `audio.downmix_stereo` + `wave_points` + evento `wave {l,r}` (`audio.py`/`Motif.qml`) — la captura
  estéreo se baja a mono ANTES de `AudioAnalyzer.feed` (no descalibra perfiles viejos); el scope
  dibuja Lissajous L/R real. Detalle y números: `docs/TRAMPAS.md` / `docs/NUMEROS-MEDIDOS.md`.
- `audio.dirt_from` + `AudioAnalyzer._smooth_dirt` + campo `d` de `aud` → `crtDirt`/`crtDirtMult`
  (`crt.dirt`) — planitud espectral local (ruido/guitarras) escala SÓLO `noiseAmt`. Detalle:
  `docs/NUMEROS-MEDIDOS.md`.
- `audio._cut_step`/`_smooth_hf` + campos `cut`/`cutf`/`hf` de `aud` (`audio.py`) — `cut`/`cutf`
  marcan un corte seco al bajar de golpe y la fuerza de vuelta; `hf` es flujo espectral, reusa el
  espectro que `dirt` ya calculaba. Detalle: `docs/TRAMPAS.md` ("Detalle movido: mapa técnico").
- `shell/React.js` — funciones puras del reloj del tubo (`cutDim`, `backFlash`, `fizz`, `grain`,
  `grainAdvance`) que llaman `Crt.qml` Y el banco `previews/reaccion/` (misma fuente). Mapean
  `cut`/`cutf`/`hf` a uniforms de `crt.frag` sin sumar animación por pantalla. Fase del grano
  acumulada en QML, no en el shader (TRAMPAS: salta al tocar la velocidad).
- `crt.resting` + `tubeAccum` (`Crt.qml`) — pausa con letra puesta: reloj a 15 fps, pump frenado,
  sin estela; vuelve con el primer `pos`/`aud`. Detalle: `docs/TRAMPAS.md` ("Detalle movido: mapa técnico").
- Guardia de instancia única: el lock guarda el PID del dueño; `stop` mata por pid. Detalle: `docs/TRAMPAS.md`.
- `tests/` — ~690 tests, stdlib puro.
- `previews/showreel/` — reel de 15 s con animaciones NUEVAS, sin integrar (render offscreen
  determinista, `./render.py`). Qué módulo y cómo integrarlo: su `README.md`.
- `previews/crt-motifs/` — banco de los 8 motivos de loop de 15 s, YA INTEGRADOS: `shell/<Kind>.qml` +
  `MotifBase.qml` (Shapes vía `MShape.qml`, NUNCA Canvas de pantalla entera: TRAMPAS). Ver su `README.md`.

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
sacara el dibujo buscado. El forzado pisa pool, hold, filtro de validez y palabra clave, y se ve
aunque no suene nada; la letra sigue dibujándose encima. Kinds válidos: `fatal crt motif --help`.

Autostart: **UNO solo** `exec-once` en `execs.conf` con `sleep 6 && cartelitos restart`. `restart`
deja estado limpio aunque haya quedado media instancia. No reintroducir un segundo (`docs/TRAMPAS.md`).

## Dónde está el resto (leer sólo lo que toca)

**Tope de este archivo: 19.000 caracteres.** Es el mapa mental + índice.

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
