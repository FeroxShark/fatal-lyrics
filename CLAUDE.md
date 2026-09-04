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
  motif que huye (`foreshadow`) y el aro que cuenta (`ring`, `shell/Ring.qml`).
- **Un salto largo se ve viajar.** Si la frase cae en una pantalla que no es la de al lado, la
  perilla `hop` (`corridor|interference|both|off`) manda una franja de scanlines cruzando cada
  pantalla del medio y la glitchea al pasar. El reloj del viaje (180 ms) lo publica `shell.qml`
  UNA vez (`crtHopStart`) y cada monitor lo lee: es una sola franja atravesando la pared.
- **En el CRT la letra no se clona.** Hay una pantalla enfocada, la frase sigue en la de al lado y
  el pedazo ya leído queda quemado abajo. Las repeticiones se cortan en el daemon
  (`split_repeats`) y cada golpe cae en otra pantalla. `focus = "all"` vuelve al comportamiento
  viejo.
- **La letra va en el idioma en que se canta.** Hay una cadena de proveedores
  (`lrclib` match exacto → `lrclib` búsqueda → `NetEase`), se prueba con el título
  original y después con el limpio, y gana el primer `ok`. De NetEase se usa `lrc`
  y **nunca** `tlyric`, que es la traducción al chino. Nada de campos de traducción,
  en ningún proveedor.
- **Casi todo lo raro tiene una razón medida.** Los gotchas caros están documentados EN EL CÓDIGO.
  Leerlos antes de "optimizar" algo que parece raro.

## Mapa

- `bin/fatal` — CLI: `on|off|restart|status|config|demo|crt on|off|toggle|sync +|-|sing on|off`.
- `shell/shell.qml` — reparte qué dibuja cada pantalla.
- `shell/Crt.qml` + `shell/crt.frag(.qsb)` — el tubo: vidrio, fósforo, scanlines, rotura.
- `shell/Motif.qml` — seis animaciones para las pantallas sin letra.
- `shell/Ring.qml` — el aro que se consume contando la línea que viene.
- `cartelitos/lyrics.py` — cadena de proveedores, cache, LRC "enhanced" (tiempo por
  palabra) y `split_repeats`.
- `cartelitos/offsets.py` — corrección de sync por artista (`offsets.toml`), separada de
  `config.py` porque la escribe el propio daemon, no Ferox a mano.
- `packaging/PKGBUILD` + `.SRCINFO` — listos, build probado con makepkg.
- `docs/demo-dialogs.gif`, `docs/crt-mode.jpg` — para el README.
- `tests/` — 433 tests, stdlib puro.

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

Autostart: **UNO solo** `exec-once` en `execs.conf` con `sleep 6 && cartelitos restart`. `restart`
deja estado limpio aunque haya quedado media instancia. (Hubo dos exec-once compitiendo: el de
`hyprland.conf` arrancaba en t=0 sin monitores y el de `execs.conf` veía sus pidfiles y hacía
no-op → boot roto. No reintroducir un segundo.)

## Trampas

- **Lanzar el overlay con `qs -p ... &` pelado NO sirve:** muere junto con la shell que lo lanzó
  (una terminal que se cierra, un tool call de Claude, un script efímero), sin log ni coredump —
  parece magia negra. `bin/fatal` usa `spawn()` con `setsid` y el PID lo escribe el propio hijo
  antes del `exec` (con `setsid`, el `$!` del padre no sirve).
- **La cache de letras distingue "no hay letra" de "no llegué a lrclib".** El primero se cachea
  (7 días), el segundo se reintenta y **nunca** se cachea. Desde que existe el estado "plain"
  (T0.14: sólo hay texto sin sincronizar), el status se guarda **explícito** en el JSON — antes se
  infería de si `lines` venía con contenido, y "plain" también tiene `lines` no vacío, así que se
  habría leído como "ok" al volver de cache.
- **`fatal status` tampoco puede preguntarle nada al daemon** (misma razón que el
  punto de abajo, al revés): el proveedor de la letra sale de un archivo que escribe
  el daemon, `$XDG_RUNTIME_DIR/cartelitos/lyrics`, **ya formateado**. Parsear JSON
  desde bash para imprimir una línea no vale la pena. Lo borra `fatal stop` y no se
  imprime con el daemon muerto: si no, es la letra de la sesión anterior.
- **El daemon vivo no es alcanzable desde afuera salvo por archivo.** El socket Unix es
  unidireccional (daemon → overlay); un proceso corto como `bin/fatal` no puede escribirle nada al
  daemon por ahí. Mismo mecanismo que `crt`/`tune`: un archivo en `$XDG_RUNTIME_DIR` que un hilo
  del daemon vigila por mtime (`cartelitos-sync`, para el gesto de T0.13). El menú de bandeja es
  la excepción: corre DENTRO del proceso del daemon, así que llama directo a un método sin pasar
  por ningún archivo.
- **`Quickshell.screens` cambiando no siempre re-dispara un binding que lo lee adentro de una
  función** (p.ej. `matchScreens()`). Para el hotplug de monitores (T0.11) hizo falta forzarlo a
  mano: un `property int screensGen` que un `Connections { onScreensChanged }` incrementa, y la
  función lee esa property (aunque no la use) sólo para crear la dependencia.
- **`Super+Shift+Left/Right` ya estaban tomados** (mueven la ventana enfocada, en
  `hyprland/keybinds.conf`). El gesto de sync (T0.13) usa `Super+Alt+Left/Right` en su lugar —
  chequear binds existentes antes de proponer una combinación nueva.
- **Alcanza con que UN proveedor no llegue para que el resultado sea `error`**, no
  `none`. `none` se cachea 7 días: cachearlo porque NetEase estaba caído deja el tema
  marcado como instrumental por una semana.
- **La búsqueda de NetEase es difusa a lo bruto:** con una consulta que no existe
  igual devuelve cinco temas cualesquiera. Lo único que separa el match del relleno
  es la duración (±3 s) — no sacar ese filtro. Su LRC además trae la ficha técnica
  como versos con marca de tiempo (`作词`/`作曲`/`制作人`): sin filtrarla, el tema
  arranca con tres cartelitos de créditos.
- **Los tiempos por palabra tienen que ser tantos como `texto.split()`.** En el LRC
  "enhanced" un tramo `<t>` puede traer dos palabras; si contara como una, todo lo
  que sigue queda corrido. `_parse_words` le da a CADA palabra del tramo el tiempo
  del tramo, así el largo coincide por construcción y el overlay puede mapear por
  índice. En el CRT se usan **sólo** si esa pantalla muestra la línea entera: con
  `split` o con el director, el índice no es el mismo y `reveal` corre sobre la
  ventana del pedazo, no la de la línea.
- **Carrera de la búsqueda de letra:** un hilo viejo pisaba la letra del tema nuevo. Está resuelto
  con lock + contador de generación. No sacar ninguno de los dos.
- **caelestia dibuja submenús pero NO checkmarks** (su `TrayMenu.qml` pinta sólo icon+text). El
  estado de un toggle va en el **texto** del ítem, no en un `Gtk.CheckMenuItem`. El menú de bandeja
  se prueba sin tocar el mouse: `busctl --user ... com.canonical.dbusmenu GetLayout` / `Event ...
  clicked`.
- **`qs ipc call` con args está roto en quickshell-git 0.3.0** → se usa el socket Unix.
- **Medir CPU:** el de los `playerctl` hijos NO aparece en `utime`/`stime` de `/proc/<pid>/stat`.
  Usar `resource.getrusage(RUSAGE_CHILDREN)` (real: 3.8 ms por spawn).
- **El drag de la funda realimentaba el jitter** (el temblor movía la ventana y eso agrandaba el
  delta): `dragHeld` excluye `jx`/`jy` y `dragBy` clampea. Umbral de 5 px para distinguir click de
  arrastre.
- Poll fino de 0.3 s **sólo** si suena y hay letra cargada; si no, 1/s. La búsqueda de letra va en
  hilo aparte (antes bloqueaba el loop hasta 20 s si lrclib andaba lento).
- **En `Component.onCompleted` de `win` (el `PanelWindow` del cartel, con `required property
  modelData`), un `id` declarado MÁS ABAJO en el archivo no resuelve** si se lo llama directo en el
  cuerpo del handler (`ReferenceError`) — el `required property` lo vuelve un delegate "bound" y
  ahí la resolución de `id` hacia adelante no es la misma que en un binding de propiedad normal
  (esos sí resuelven adelante sin problema, ver `closeBtn` referenciado por un `Text` anterior) ni
  que dentro de una función (`die()` llama a `deathAnim` declarado bien después, y anda). Regla
  práctica: toda animación que se dispare desde `Component.onCompleted` de `win` se declara ANTES
  de ese handler, no después.
- **Los pedazos del modo `iown` se miden con la línea entera, no con `dur`.** La palabra viaja
  con `crtProgress()`, que se reparte sobre toda la línea; si la ventana del chunk es `dur`
  (los ~2 s de los otros modos) la palabra se apaga a un tercio de camino y la pared queda
  vacía. La ventana es `Math.max(t0 + dur, line.t1)`.
- **El `ShaderEffectSource` del burn-in se agrega a la escena antes de que el cartel muera,
  con `opacity: 0`.** Adentro de un item `visible: false` no dibuja nada, y entonces la captura
  de `die()` sale vacía. El `visible` mira `dying || ghosting`, no sólo `ghosting`.
- **La `phase` del evento `bpm` es la EDAD del último golpe, no su marca de tiempo.** El reloj
  del daemon (`time.monotonic`) y el del overlay (`Date.now`) no son el mismo: un instante crudo
  del daemon allá no significa nada. El overlay ancla con `Date.now() - phase*1000`.
- **Los intervalos del `BpmTracker` se pliegan al rango 300–1200 ms, salvo los huecos.** Marcar
  corcheas (250 ms) o perder un bombo (1000 ms) es el MISMO compás; pero un hueco de más de 2.4 s
  es una pausa o la captura caída, y plegarlo daría un tempo inventado: ese se tira entero.
- **El período se re-centra sobre su propio promedio, no se lee del bin.** Con la ventana de ±8%
  clavada en el centro del bin, un centro corrido 10 ms recorta una de las dos colas y el promedio
  se va detrás del recorte: 3 BPM de error medidos con jitter de ±20 ms.
- **El pulso del compás en el overlay es un poll de 25 ms, no un `Timer` con el intervalo del
  tiempo.** Re-anclar la fase obligaría a `restart()`earlo, y eso le rompe el binding de `running`
  (queda prendido con el tubo apagado). Con la resta contra `lastBeatAt`, re-anclar es asignar
  una property.
- **Una perilla nueva son CUATRO lugares, no tres:** `DEFAULTS` + `_CONFIG_COMMENTS`
  (`config.py`), `CONFIG_EVENT_MAP` (`ipc.py`), `_configEventMap` (`shell.qml`) y `SETTINGS`
  (`setup.py`) — sin este último la perilla existe pero no aparece en `fatal config`.
- **El reflejo (`mirror`) son 8 tajadas, no una imagen con degradado.** El degradado necesitaría
  `OpacityMask` de `Qt5Compat.GraphicalEffects`, que este shell no importa en ningún lado.
- **El cartel `kind: "hang"` muere solo sin plumbing propio:** nace con `pushDialog(..., false)`,
  así que su `gen` queda en el `lyricGen` del momento y `lyricGen` sólo sube con un verso de
  verdad — `shouldDie` compara esas dos cosas.
- **El aviso `cue` sólo llega en la SEGUNDA escucha del tema** (necesita el mapa de energía
  guardado): no se puede ver con `fatal demo` ni con un tema nuevo, sólo en el log del daemon.
- **El umbral del karaoke se mide con el cuarto CALLADO, y en muestras, no en reloj.** Si la
  ventana de 20 s se alimenta también con la voz, el percentil 60 sube hasta la voz y el modo se
  apaga solo en la mitad del estribillo; si además se filtra por reloj, un estribillo largo la
  deja entera vencida y el primer respiro la borra. Es un deque de las últimas 200 muestras
  calladas (llegan a 10 Hz).
- **Los dos multiplicadores de la histéresis del karaoke son > 1.** El umbral ES el nivel del
  cuarto: con el de apagado por debajo de 1, un ruido de fondo parejo (un ventilador) queda para
  siempre encima de su propio umbral y el modo no se apaga nunca más.
- **`cartelitos-sing` es un TIMBRE, no el estado** (al revés que `cartelitos-crt`): el estado es
  la perilla `[behavior] sing` del TOML, que es la que viaja al overlay y sobrevive al reinicio.
  `fatal sing` sólo deja el pedido escrito y el daemon lo pasa a la config (igual que `fatal tune`).
- **Si la entrada por default es un `.monitor`, el karaoke no graba.** Lo que entraría por ahí es
  la propia música y el modo diría "está cantando" cada vez que suena un tema.
- **Oscurecer el tubo con `stage.opacity` funciona porque `crt.frag` ya multiplica por
  `qt_Opacity`.** Si alguna vez el shader deja de hacerlo, el modo karaoke se queda sin su
  apagado y hay que poner un rectángulo negro encima en su lugar.
- **`crtShotFor()` no puede leer NADA vivo del root.** Es la función que se evalúa sobre una línea
  que todavía no llegó: cualquier cosa que mire el estado del momento (así estaba `crtTrackStart`)
  hace que la predicción y lo que después se ve no sean la misma cosa. Todo entra por el objeto de
  la línea. Lo único que la predicción no puede saber es la parte del tema — por eso una línea que
  cae en un drop se rehace como IOWN encima, y sólo eso.
- **El reloj del salto es del root, no de cada pantalla.** `crtHopStart` es el `Date.now()` en que
  arrancó, publicado una vez; cada monitor calcula su tramo contra ESE número. Con un reloj por
  monitor la franja entra en la segunda pantalla antes de salir de la primera y deja de leerse como
  una sola. Cancelar es asignarle 0 — lo hace `crtForget()`, así que el hotplug, la config y el
  cambio de tema cortan el salto sin plumbing propio.
- **La pantalla del medio corre a 20 fps** (el `Timer` del instrumental; el `FrameAnimation` de
  `Crt.qml` sólo corre con texto o en standby). Un salto de 180 ms leído desde ahí serían cuatro
  posiciones: el salto tiene su propio `FrameAnimation`, prendido sólo mientras dura.
- **Los tres cuadros del glitch del salto se cuentan en CUADROS**, con un contador que baja en el
  mismo `FrameAnimation`. Un `Timer` de 50 ms es otra cosa: en una pantalla que va lenta el color
  separado queda puesto más de lo que dura el paso de la franja.
- **En el QML la perilla `hop` se llama `crtHopMode`:** `crtHop` ya era el descriptor del salto de
  la FASE 0 (`{from, to, dir}`). El mapeo es `crt_hop → crtHopMode`.
- **`qsb` no está en el PATH** (vive en `/usr/lib/qt6/bin/qsb`). Después de recompilar, verificar
  que los uniforms nuevos entraron: `qsb --dump shell/crt.frag.qsb | grep <nombre>`. Un uniform que
  no está deja la property del `ShaderEffect` atada a nada, sin un solo warning.
- **El `next` lleva también los `segs`.** El corte de las repeticiones ("take, take, take") se hace
  en el daemon: sin mandarlo, la predicción reparte la línea de una forma y la línea de verdad
  llega con otra.
- **El shot guardado se tira en el `clear`, en el hotplug y en la config** (`crtForget()`). Sin lo
  del `clear`, los pedazos del reparto del tema anterior sobreviven al cambio de tema y
  `crtChunkState` los sigue devolviendo.
- **Un `Motif` no se apaga pisándole `opacity` desde afuera:** eso se lleva puesto el
  acompañamiento del golpe (`surge`), que es lo que hace que la pared entera pegue junta. Va por la
  property `dim`, que es un factor aparte.
- **El log del overlay tiene códigos de color EN EL MEDIO del prefijo:** `grep "qml:"` no matchea
  nunca (entre `qml` y los dos puntos hay un escape ANSI). Se grepea el texto propio:
  `grep -a "crt:" $XDG_RUNTIME_DIR/cartelitos/qs.log`.
- **`fatal demo` no sirve para probar nada de la anticipación:** los carteles de demo van sin letra
  de verdad, así que `next` viaja en `null` y `t0`/`t1` en 0. Hace falta música con letra
  sincronizada. Para probar sin depender de qué suena, se le puede hablar al overlay directo por
  `$XDG_RUNTIME_DIR/cartelitos.sock` (el socket es del overlay, el daemon es el cliente).
- **`mock.patch.dict` COPIA los valores:** mutar el dict que se le pasó no toca `config.CFG`. Un
  test que apagaba `sing` así dejó la captura girando para siempre y colgó la suite entera.

## Números medidos

- CRT prendido: ~19% de un core. Apagado: 1.7% (sin captura, sin texturas).
- El análisis de audio es Python puro sobre `pw-record` (sin cava, sin numpy): 0.79% de CPU.
  Arma el mapa del tema por percentil de energía dentro de la propia canción
  (quiet/verse/build/drop) y lo cachea: la segunda vez que suena, anticipa los golpes.

## Glosario

- **cartelito** — un diálogo de error con una línea de la letra.
- **funda** — la ventana con la portada del disco (bevel Win95, disco que asoma y gira).
- **burn-in** — la silueta quemada que queda cuando un cartel muere.
- **cascade** — muerte en cadena de los carteles al cambiar de tema.
- **karaoke** — pintar la línea actual palabra por palabra.
- **motif** — la animación que va en las pantallas que no tienen letra.

## Pendientes

- **AUR:** `packaging/` listo y probado. Falta que Ferox cree cuenta en aur.archlinux.org y
  registre su clave SSH (1Password); después clonar
  `ssh://aur@aur.archlinux.org/fatal-lyrics-git.git`, copiar `packaging/` y push.
- README: falta la captura del menú de bandeja y la de `fatal config`. Receta del GIF:
  `wf-recorder -o <salida>` + ffmpeg `palettegen(max_colors=96)` / `paletteuse`. No hay gifsicle.
- README: documenta sólo lrclib, pero desde FASE 1 la búsqueda encadena un segundo proveedor
  (music.163.com/NetEase) y le manda artista + título. Falta decir cuáles son los proveedores y
  en qué orden se prueban.
- **`docs/plans/2026-09-03-crt-tanda2.md`: hechas las FASES 0, 1 y 2** (perillas `foreshadow`,
  `ring` y `hop`). Faltan las fases 3 a 5: entradas nuevas y director por energía, ocho motifs
  nuevos, y el cierre de docs. Lo que hay que mirar a ojo está en
  `docs/plans/CHECKS-VISUALES.md`.
- **El plan de mejoras `docs/plans/2026-09-03-mejoras-fatal-lyrics.md` quedó COMPLETO** (FASE 0 a
  FASE 5). Falta probarlo cantando: el modo karaoke (`fatal sing on`) se verificó con la captura
  del micrófono andando y con los tests del `SingGate`, pero nadie cantó todavía — si el umbral
  quedó duro o blando, se toca `SING_ON`/`SING_OFF` en `cartelitos/daemon.py`.

## Decisiones cerradas (Ferox las descartó, no re-proponer)

- BSOD, sonidos, easter egg `wolf.exe` (el video de Mr Wolf es UN tema puntual — no insistir).
- Temas visuales (win95 / XP / vaporwave): le gustó la idea pero **no la pidió**. Esperar a que la
  pida.
- Defaults que él usa: `karaoke = true`, `max_dialogs = 0` (sin límite), `cascade` y `np_vinyl` en
  true.
