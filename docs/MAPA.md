# cartelitos — Mapa del código: qué hace cada archivo, propiedad y perilla, y dónde están los cachés

Movido textual desde `CLAUDE.md` (2026-10-07).

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
  `crtSceneOutroCheck` (`crt.scene = sections | all`) — la sección decide qué
  pantallas viven: la estrofa deja sólo el foco prendido, el drop enciende la pared entera y el
  final del tema apaga de a una hacia el foco. Nunca apaga la pantalla que `crtPredict()` ya
  prendió por anticipación. Detalle: `docs/TRAMPAS.md` ("Detalle movido: mapa técnico").
- `crt.screen_off` (false, Ferox 2026-09-28): sin intro ni escena que apaguen pantallas; queda el dip del corte seco.
- `crtIntroPhase`/`crtIntroScreen` + `crtIntroStart`/`Advance`/`End`/`Skip` (`shell.qml`,
  perilla `crt.intro`, `crt.intro_card`) — el cambio de tema es un evento: `clear` (why="track")
  apaga la pared, degauss, estática y la tarjeta (título/artista) en la pantalla del próximo foco,
  sin plazo: la corta `show()`. Sin apagón (`screen_off` false) + tarjeta `plain`: sólo la tarjeta,
  en el foco, con plazo (`crtIntroSoft`, `Crt.introHere`). Detalle: `docs/TRAMPAS.md`.
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
- `shell/Rows.js` + `crt.lyricRows` (`Crt.qml`) + `WordSlot.fitWidth` — en allMode (con `wholeWordsOn`) una línea larga se acomoda en renglones centrados en vez de una palabra por renglón; `Rows.pick` elige cuántos y `measure` pone el tamaño sobre ellos. Director y calidad baja siguen apilados. TRAMPAS: "El Flow del allMode apilaba". Banco: `previews/letra/` (`docs/tanda8-estado/letra-renglones-*.png`).
- `shell/Speed.js` + `crtMovRate`/`movOff` (`crt.mov_speed`, `movMin`/`movMax` en `crtPaceTable`) — la
  deriva de los motivos sigue `mov` del `aud`, INTEGRADA (nunca `t·rate`); entradas, shader y compás no.
  TRAMPAS: "El ritmo de los dibujos". Banco: `previews/movimiento/`.
- `crtCharacter` / `kickAmp` / `kickMs` / `bassHit()` / `bassGen` (`shell.qml`) + `kickPulse` (`Crt.qml`) + `bump`/`glints` (`Motif.qml`) — el golpe visible por bombo, escalado por carácter del tema; columnas `kick*` de `crtPaceTable`. Ganchos de `audio.py`: `audKick`, `audHat`, `audNov`, `songChar`. `crtDensity` mete `audMov` al sorteo, al hold y a `crtSceneFor`. TRAMPAS: "El golpe del bajo". Banco: `previews/golpe/`.
- `shell/HopRay.qml` — el rayo del salto: recorrido, cabeza, cola, degradado.
- `shell/Maze.qml`/`Maze.js` (`crt.maze_eggs`) — marcha por CONTADOR de pasos (crédito `rate`, se planta en `cut`, mira con `hf`) + huevos raros. TRAMPAS: "El laberinto".
- `shell/Swarm.qml` + `swarm.vert`/`swarm.frag` (+ `.qsb`) — la bandada, un solo `ShaderEffect` por instancias (260 flechas × 4 capas armadas en el vértice con `GridMesh` 4159×1; la palabra va en 18 `mat4`). 12 ms → 2 ms en el banco. TRAMPAS: "Swarm por shader de instancias".
- `shell/Membrana.qml` / `Cintas.qml` / `Giroscopio.qml` (+ `.frag`/`.frag.qsb`) sobre `shell/ThumpBase.qml` + `Thump.js` — los tres motivos de golpe físico (2026-10-19, en `motifKinds`/`motifFit`/`motifGroups`: membrana y cintas hot, giroscopio neutral). Cada bombo es un resorte amortiguado en forma cerrada (`Thump.js`: sobrepaso, vuelta, los golpes se suman; cámara/aros más pesados responden más tarde). Señales: `thump` ← `bassGen` (`k` del daemon, `b` de respaldo; un `rise` pulsa más flojo), `thumpAmt` ← `kickThumpAmt` (`pace.kickThump` × perilla `flicker`), `hat` ← `hatLevel` (agudos), `mov` ← `crtDensity` (`audMov`+`audNov`), `character` ← `crtCharacter` (suavizado 1,5 s; la física sale de él). `fatal crt motif membrana|cintas|giroscopio` los fuerza. Banco: `previews/crt-motifs/` (`sync-shell.sh` copia de `shell/`; en el banco `character`=-1 y derivan de BPM+mood).
- `crtEntryTable` + `crtPickEntry` (`shell.qml`) — pesos de las entradas y sorteo.
- `crtSetFor(seed, mood)` (`shell.qml`, perilla `crt.set`) — el set por tema: familia de entrada,
  scheme y fuente, de una semilla atada a `crtTrackSeed`. Los DIBUJOS no salen del set:
  `crtMotifDraw` sortea con dados cargados por lo que suena. `crt.set = "off"` vuelve al sorteo
  plano. Detalle: `docs/TRAMPAS.md` ("Detalle movido: motivos y set").
- `crtFontPools` (`shell.qml`) — mazo de fuentes por familia de entrada, elegido con el mismo dado
  que la fuente del set (sin Press Start 2P, no le gustaba): plex, space, chakra, syne, vt323,
  share, system — créditos: `shell/fonts/LICENSE-*.txt`.
- `shell/Faces.js` + `crt.face_mode` — tres caras por paleta, la sección las reparte. TRAMPAS: "Tres caras".
- `cartelitos/mood.py` — `mood_for(lines, profile_summary, bpm)`: valence/energy/bright/contrast
  determinísticos, sin red ni IA (`feedback_ia_sin_creditos`). El daemon lo manda por el socket
  como evento `mood`, hasta dos veces por tema. Detalle: `docs/TRAMPAS.md` ("Detalle movido: mapa técnico").
- `cartelitos/lyrics.py` — cadena de proveedores, cache, LRC "enhanced" (tiempo por
  palabra) y `split_repeats`.
- `cartelitos/offsets.py` — corrección de sync por artista (`offsets.toml`), separada de
  `config.py` porque la escribe el propio daemon, no Ferox a mano. Adentro vive también el
  perfil por tema (`_pending`, en memoria): lo que todavía no se ganó el derecho a durar.
- `cartelitos/settings.py` + `shell/settings.qml` — la ventana de Ajustes (`fatal ajustes`, otro
  proceso Quickshell, capa `cartelitos-settings`; `fatal config` es alias). Es la ÚNICA pantalla
  de opciones: `TABS` + `GROUPS` son el esquema (pestaña, columna, filas de tipo toggle / choice /
  slider / screens / order / text, más los botones `crt` y `sync`), la ventana lo pide con
  `--settings-json` y dibuja lo que venga, así que una opción nueva es una fila ahí. `coerce`
  valida cada valor antes del TOML (`_toml_val` no escapa: nada de comillas ni barras). Lo que se
  toca vuelve por `$XDG_RUNTIME_DIR/cartelitos-settings` (`<serie> seccion.clave=<json>`), que
  vigila `watch_settings` en el daemon; sin daemon, `--settings-set` escribe el TOML directo.
  Apuntar una fila llena el panel de abajo de la hoja con `details` (el comentario de
  `_CONFIG_COMMENTS`, `settings.detail`; si no hay, el hint), y una fila con `needs: [ids]`
  (`_needs`) se atenúa mientras alguna de esas casillas esté apagada. Los nombres de fila no se
  repiten ni igualan a un título de grupo (un test lo exige).
  Reemplazó a `tune.qml`, a los submenús de la bandeja (`tray.py` quedó en Ajustes / CRT /
  karaoke / Quit) y al menú de terminal `setup.py` (borrado 2026-10-09).
- `[keys] sync_forward` / `sync_back` / `crt_toggle` (`config.py`) + `system.key_bind_commands()` — las
  teclas del sync y del tubo. Las aplica Hyprland desde el daemon; al overlay sólo viaja el
  rótulo armado con ellas (`system.keys_hint()`, campo `keys_hint` del evento `config`): el
  tooltip amarillo `keysWin` de `shell.qml` (arriba al medio, al empezar cada tema, con el
  offset al ajustar) y la segunda línea de la ayuda de salida del tubo (`hint`, `Crt.qml`). Con config Lua
  (0.56+, `system._hypr_lua()`) van como `hyprctl eval 'hl.bind(...)'` y los modificadores en
  mayúscula (`_lua_keys`); con hyprlang, `hyprctl keyword`.
- `packaging/` — `fatal.desktop` + `fatal-lyrics.svg` (ícono, Win95) para el lanzador, que
  `install.sh` copia a `~/.local/share`; `hyprland.lua` (binds Super+Shift+Y / Super+Alt+flechas,
  `no_anim` de las capas `cartelitos*`) para el `dofile` de la config de Hyprland;
  `fatal-lyrics.service` (el autostart: unit de usuario con `fatal run`, que `install.sh` copia a
  `~/.config/systemd/user` y habilita; `fatal on|off|restart` pasan por `systemctl --user` si
  existe); `PKGBUILD`. Pantallas de Ferox hoy: DP-2 · HDMI-A-1 (carteles) · DP-1 (widgets, fuera del CRT).
- `audio.downmix_stereo` + `wave_points` + evento `wave {l,r}` (`audio.py`/`Motif.qml`) — la captura
  estéreo se baja a mono ANTES de `AudioAnalyzer.feed` (no descalibra perfiles viejos); el scope
  dibuja Lissajous L/R real. Detalle y números: `docs/TRAMPAS.md` / `docs/NUMEROS-MEDIDOS.md`.
- `audio.dirt_from` + campo `d` de `aud` → `crtDirt`/`crtDirtMult` (`crt.dirt`) — planitud espectral
  (ruido/guitarras) escala SÓLO `noiseAmt`. Detalle: `docs/NUMEROS-MEDIDOS.md`.
- `audio._cut_step`/`_smooth_hf` + campos `cut`/`cutf`/`hf` de `aud` (`audio.py`) — `cut`/`cutf`
  marcan un corte seco al bajar de golpe y la fuerza de vuelta; `hf` es flujo espectral, reusa el
  espectro que `dirt` ya calculaba. Detalle: `docs/TRAMPAS.md` ("Detalle movido: mapa técnico").
- Golpes por instrumento y carácter (`audio.py`, 2026-10-19; el overlay todavía NO los usa), todo
  sobre la misma FFT, sin perfil (sirve en la primera escucha). Campos de `aud`: `k` bombo
  (40-150 Hz contra su promedio corto, refractario 200 ms; fuerza 0..1 = filo × peso en la mezcla,
  0 = no hubo); `ht` agudos (flujo relativo 2.5-8 kHz, 60 ms; `hf` queda en 125-6000 Hz porque
  `mov` comparte su `hf_raw`); `nov` 0..1 (coseno entre la forma de 6 bandas de los últimos 2 s y
  los 2 s previos: capa que entra al mismo volumen); `rise`/`fall` (EMA 2 s − EMA 8 s de `mov` y
  del nivel en dB, sostenida >1 s; un bloque, magnitud 0..1, mudos los primeros 4 s). `k`/`ht`/
  `rise`/`fall` fuerzan el envío (si no, caen en el bloque salteado por `AUDIO_MIN_SEND`). Evento
  aparte `char {v}` 0..1 calmo..agitado (`CharTracker`, EMA 6 s, se manda al moverse >0.05):
  BPM con conf ≥0.5 + `mood.energy` (perfil guardado, o el en vivo desde 20 s) + onsets/s de ~20 s.
  Tests: `tests/test_golpes.py`. CPU: +0.05 ms por bloque (~+0.15 % de un núcleo).
- `shell/React.js` — funciones puras del reloj del tubo (`cutDim`, `backFlash`, `fizz`, `grain`,
  `grainAdvance`) que llaman `Crt.qml` Y el banco `previews/reaccion/` (misma fuente). Mapean
  `cut`/`cutf`/`hf` a uniforms de `crt.frag` sin sumar animación por pantalla. Fase del grano
  acumulada en QML, no en el shader (TRAMPAS: salta al tocar la velocidad).
- `crt.resting` + `tubeAccum` (`Crt.qml`) — pausa con letra puesta: reloj a 15 fps, pump frenado,
  sin estela; vuelve con el primer `pos`/`aud`. Detalle: `docs/TRAMPAS.md` ("Detalle movido: mapa técnico").
- Guardia de instancia única: el lock guarda el PID del dueño; `stop` mata por pid. Detalle: `docs/TRAMPAS.md`.
- `tests/` — stdlib puro.
- `previews/showreel/` — reel de 15 s con animaciones NUEVAS, sin integrar. Ver su `README.md`.
- `previews/crt-motifs/` — banco de motivos de loop de 15 s, YA INTEGRADOS (Shapes vía `MShape.qml`, NUNCA Canvas de pantalla entera: TRAMPAS). `./sync-shell.sh` antes de renderizar el laberinto. Ver su `README.md`.

Cachés: `~/.cache/cartelitos/{lyrics/,audio}` (letras; mapa de energía por tema). Purga al arranque: letras
`purge_cache` (OK 180 días, "no hay letra" 7), perfiles `audio.purge_profiles` (180 días sin escucharse, por mtime).
