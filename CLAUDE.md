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
  (`docs/plans/2026-09-04-fluidez-referencia.md`): lo fluido no es tener más cuadros, es que
  todo se mueva con la misma gramática, con holds largos entre evento y evento y una deriva de
  velocidad uniforme por debajo que nunca para.
- **REGLA: los eventos tienen PRESUPUESTO, y es la perilla `pace`** (`calm | normal | wild`,
  default `normal`, tabla `crtPaceTable` en `shell.qml`). No es una velocidad: nada se mueve más
  despacio. Es cuántas cosas tienen permiso de pasar por minuto — cuánto dura el dibujo de una
  pantalla antes de poder cambiar (12 s), cada cuánto la pared puede cambiar de canal (20 s),
  cada cuánto una pantalla puede romperse (4 s), y qué tan grande es el latido de la cámara y
  del motivo. `wild` devuelve exactamente los números de la tanda 3. Un número de amplitud o de
  frecuencia nuevo va a la TABLA: repartido en ternarios por los archivos, `wild` deja de ser
  verificable.
- **Una pantalla sin letra no dibuja cualquier cosa: dibuja algo del tema.** Los motivos de la
  tanda 2 leen lo que el tubo ya sabe — `dunes` es el único paisaje (el paisaje está quieto y lo
  que se mueve es la cámara, re-sembrada en cada aparición), `static` forma una vez por compás la
  primera palabra de la línea que VIENE, `textsea` hace correr la letra entera con el verso que
  suena encendido, y `eyes` es UN ojo grande mirando a la pantalla que tiene la frase — pupila
  estirada hacia allá, párpado entrecerrado en calma — con dos o tres ojos chicos yendo y
  viniendo por los bordes (a los costados si la pantalla es apaisada, arriba y abajo si es
  vertical), y gira hacia el destino durante el aviso del salto. Los cuatro de la segunda mitad leen el
  ritmo: `ekg` escribe un QRS por tiempo (del `tick` cuantizado, no del bombo crudo),
  `rorschach` abre la mancha bajando el umbral con el volumen, `plasma` deja que los graves
  empujen las bolas para arriba y `tunnel` viaja más rápido cuanto más fuerte suena. Y `scope`
  cierra la figura de Lissajous cuando el compás es confiable (la relación entre los ejes sale
  de la parte del tema); `stars` salta al hiperespacio en el drop.
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
- **La letra va en el idioma en que se canta.** Hay una cadena de proveedores
  (`lrclib` match exacto → `lrclib` búsqueda → `NetEase`), se prueba con el título
  original y después con el limpio, y gana el primer `ok`. De NetEase se usa `lrc`
  y **nunca** `tlyric`, que es la traducción al chino. Nada de campos de traducción,
  en ningún proveedor.
- **Casi todo lo raro tiene una razón medida.** Los gotchas caros están documentados EN EL CÓDIGO.
  Leerlos antes de "optimizar" algo que parece raro.

## Mapa

- `bin/fatal` — CLI: `on|off|restart|status|config|demo|crt on|off|toggle|sing on|off` y
  `sync +|-|show|reset [<artista>|all]` (los dos últimos NO necesitan el daemon).
- `shell/shell.qml` — reparte qué dibuja cada pantalla.
- `shell/Crt.qml` + `shell/crt.frag(.qsb)` — el tubo: vidrio, fósforo, scanlines, rotura.
- `shell/Motif.qml` — dieciséis animaciones para las pantallas sin letra: reparte propiedades y
  elige cuál dibuja. Las dieciséis son un `Component` cada una y las pone **UN solo `Loader`**
  (`sourceComponent` según `kind`): dos motivos no pueden estar vivos a la vez. Las que tienen
  física propia viven al lado, un archivo cada una — `Ocean.qml`, `Pond.qml`, `Dunes.qml`,
  `Static.qml`, `Rorschach.qml`, `Plasma.qml` y `Tunnel.qml` (con su `.frag` + `.qsb`), más
  `Ekg.qml` (Canvas), `TextSea.qml`, `Eyes.qml` y `Eye.qml` (el dibujo del ojo, que usan el
  motivo `eye` y la grilla `eyes`). Lo que se dibuja con items sueltos (el radar, la lluvia, el
  hiperespacio, la carta de ajuste, el osciloscopio) sigue adentro de `Motif.qml`.
- `motifKinds` + `motifWords` + `motifAllowed` (`shell.qml`) — la lista, las palabras de la letra
  que eligen uno a propósito, y el filtro de los que ahora mismo no tienen con qué dibujarse.
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
- `cartelitos/lyrics.py` — cadena de proveedores, cache, LRC "enhanced" (tiempo por
  palabra) y `split_repeats`.
- `cartelitos/offsets.py` — corrección de sync por artista (`offsets.toml`), separada de
  `config.py` porque la escribe el propio daemon, no Ferox a mano. Adentro vive también el
  perfil por tema (`_pending`, en memoria): lo que todavía no se ganó el derecho a durar.
- `[keys] sync_forward` / `sync_back` (`config.py`) + `system.key_bind_commands()` — las
  teclas del sync. NO viajan al overlay: las aplica Hyprland desde el daemon.
- `packaging/PKGBUILD` + `.SRCINFO` — listos, build probado con makepkg.
- `docs/demo-dialogs.gif`, `docs/crt-mode.jpg` — para el README.
- `tests/` — 495 tests, stdlib puro.

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
  **Excepción: las de `[keys]` son TRES.** No viajan al overlay (las aplica Hyprland desde el
  daemon), así que meterlas en los dos mapas de eventos sería una property muerta en
  `shell.qml`. Lo fija `test_the_key_binds_do_not_travel_to_the_overlay`: no "arreglarlo".
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
- **El bind por default NO se escribe.** Las teclas del sync viven en la config de Hyprland
  de Ferox (`~/.config/hypr/custom/keybinds.conf`, con `unbind` antes de cada `bind`).
  Mientras `[keys]` valga lo mismo que `DEFAULTS`, el daemon no corre ni un `hyprctl`: el
  atajo ya está y escribirlo otra vez sería tenerlo dos veces. Cuando cambia, es SIEMPRE
  `unbind` del anterior y después `bind` del nuevo — **volver al valor de fábrica también
  rebindea**, porque el unbind de antes se llevó puesto el bind del archivo de Hyprland y sin
  eso la tecla queda muerta hasta el próximo reload del compositor.
- **Un reenvío de la MISMA línea no puede consumir la predicción.** `sync()` resetea el
  índice del daemon a propósito, así que cada golpe de sync devuelve el mismo verso ~0.3 s
  después. `show()` lo tomaba por una línea nueva y se comía el reparto anticipado para la
  SIGUIENTE: la frase saltaba de pantalla en cada golpe (`hop sweep` justo detrás de cada
  rótulo). El flag `again` (mismo `text` y mismo `t0`) hace que la línea que vuelve conserve
  su reparto, con el serial re-sellado — `crtShot` sólo acepta el override si el serial
  coincide con el de la línea. Tampoco se rehace como IOWN: mover la letra por haber tocado
  el sync es exactamente lo que se estaba arreglando.
- **El aviso del sync NO puede ser un `show`.** Con el tubo prendido un `show` PASA A SER la
  línea de la letra: avisar del ajuste borraba justo el verso que se estaba tratando de
  sincronizar. Va por un evento propio (`sync`) y el overlay decide qué dibujar — el rótulo
  chico en la pantalla enfocada o el cartel de Windows —, porque es el que sabe si el tubo
  está arriba.
- **El rótulo del sync apaga el motivo de su pantalla** (`dim` a 0, igual que el aro). Con
  letra la pantalla enfocada no dibuja ningún motivo, pero en un instrumental sí: ahí el
  número caía encima del dibujo y sin contraste contra él.
- **El rótulo del sync se rearma con `syncGen`, no con el número.** Dos ajustes opuestos
  dejan el mismo offset acumulado y el segundo no se vería nunca.
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
- **El reparto del reloj del salto es 22 % origen / 56 % las del medio / 22 % destino**, y después
  quedan 150 ms de cola apagándose encima de la línea que ya entró. Por eso `hopClock` llega a
  `1 + hopTailFrac` y no a 1. En el salto a la de al lado no hay medio y el reparto es 45 / 55:
  con los 22/56/22 clavados, el 56 % del reloj no lo dibujaría nadie y el rayo desaparecería a
  mitad de camino. Los dos números salen del ROOT (`crtHopSplit0` / `crtHopSplit1`), como el
  reloj: repartidos por pantalla se despegarían.
- **El rayo del salto vive en `stage`, NO adentro de `camera`.** Su recorrido se mide contra los
  bordes del tubo: con el plano de la sección encima agarraría por un borde que no es el borde.
  Igual pasa por el vidrio, que es lo que importa.
- **La pantalla del medio corre a 20 fps** (el `Timer` del instrumental; el `FrameAnimation` de
  `Crt.qml` sólo corre con texto o en standby). Un salto leído desde ahí serían siete posiciones:
  el salto tiene su propio `FrameAnimation`, prendido sólo mientras dura (y mientras dura la cola).
- **Ningún glitch visible dura menos de 120 ms, y se miden por RELOJ, no por cuadros.** (Al revés
  de lo que decía esta nota hasta la tanda 3: tres cuadros son 50 ms a 60 Hz y 15 a 200 Hz — uno
  de los monitores de prueba va a 200 —, así que contar cuadros garantizaba que en la máquina que
  podía pagarlo el efecto no se viera.) El corrimiento de canales del rayo, el doble aro del `cue`
  y el ruido del cambio de canal tienen ese piso; el del rayo además termina con UN cuadro al
  doble, porque un efecto que simplemente para no deja nada.
- **El borde por el que cruza el rayo lo decide el ROOT y alterna, no se sortea** (`crtHopEdge`,
  antes `crtHopY`, que era una altura al azar). Dos saltos seguidos por el mismo borde se leen
  como una decoración fija, y sorteando salen repetidos igual. El log dice `edge=top|bottom`.
- **El aro cuenta por RELOJ contra el `due` del daemon; el ritmo sólo dibuja** (tanda 4, al revés
  de lo que decía esta nota hasta la tanda 3). `eaten = 1 - left/span` cada cuadro, y el compás o
  el grave sólo mueven el mordisco (±2 %, vuelve solo en `Motion.enterFastMs`). Comiendo por golpe
  el arco quedaba a un tercio cuando el tema pegaba cada tres segundos, y en `beat` sin ticks se
  quedaba parado hasta que vencía el compás. El `due` es del daemon (`next.due`), en posición
  CRUDA del player: el `t0` de la letra llega `behavior.offset` + el del artista tarde, y con un
  `fatal sync +` de 0.3 s el aro no colapsaba nunca. `crt: ring mode=beat|kick|lineal` sigue en el
  log, pero ahora es el modo del DIBUJO.
- **El aro sólo aparece en el hueco SIN VOZ, y eso no se puede leer del `t1`:** el `t1` que manda
  el daemon es el `t0` de la línea siguiente. El fin de la voz lo estima el daemon
  (`lyrics.voice_end`, viaja como `v_end` en el `show`): con LRC "enhanced", el último tiempo por
  palabra más 0.45 s; sin tiempos, 0.32 s por palabra más 0.6. Y ese hueco tiene que pasar de
  `crt.ring_gap` (10 s, tanda 4): el aro NO es una flecha, es el aviso de que el tema se fue a
  instrumental. Entre verso y verso no aparece nunca, aunque la línea cambie de pantalla — dónde
  cae la letra lo dice el rayo. OJO: el hueco es el SIN VOZ, no la distancia entre versos: con
  una línea de cuatro palabras la voz se come ~1.9 s, así que 11 s entre `t0` son 9.1 s de
  silencio y no llevan aro. Sin `v_end` (daemon viejo, o un driver de `docs/plans/`) el hueco no
  se sabe y no hay aro: leerlo como largo es el aro de vuelta en cada verso. El que prende y apaga es `crtRingLive` en el ROOT, no un binding de
  `Crt.qml`: `show()` le pregunta dónde ESTABA el aro para elegir la entrada de esa pantalla, y en
  ese instante falta ~0 ms para la línea — cualquier condición sin memoria contesta "en ninguna"
  siempre. En un hueco largo aparece recién cuando faltan 8 s; antes de eso la pantalla es del
  motif. El log dice `crt: ring armed|zero|dash`.
- **El aro llega a cero en la hora, pero la raya sale con la LÍNEA.** El `show` cae 0–300 ms
  después del instante real (el poll del daemon): entre el cero y la línea el aro se queda quieto
  en "0.0", y recién cuando llega la frase sale la raya con la rotura. Un colapso que entrega en
  la hora se gasta el portero (`hit`) justo antes de la entrada, y una raya que se corta seco
  deja el aro apagado antes de que aparezca la letra. Si no llega en medio segundo, se apaga solo.
- **Las hebras del aro acumulan SU ángulo, cuadro a cuadro.** Misma trampa que el túnel y el
  hiperespacio: con `ángulo = reloj × velocidad` cualquier cambio de tempo multiplica un reloj de
  miles de segundos y las hebras se teletransportan.
- **Las familias de la mancha son PARÁMETROS, no cinco ramas** (`famSpike`, `famLobe`, `famHole`,
  `famSx`, `famSy`, `famSpat`). Así cruzar de una a otra es interpolar seis números con un
  `Behavior` en QML y el shader sigue siendo UNA evaluación: mezclar dos evaluaciones serían
  dieciséis octavas de fbm por píxel para cambiar una silueta.
- **Todo dibujo nuevo se prueba con el ancho y el alto dados vuelta.** `DP-4` es vertical y el
  compositor ya se la entrega al overlay como 1080×1920, así que un `grim -o DP-4` ES la prueba.
  Los ojos reparten los chicos según la forma (a los costados si `w > h`, arriba y abajo si no).
- **La palabra del IOWN se mide contra la CÁMARA, no contra la pantalla.** El IOWN cae en el drop,
  que es el plano más cerca (1.6): midiendo contra el ancho pelado la palabra sale cortada por los
  dos lados. Va dividida por `sectionZoom * camZoom * cueZoom`.
- **El IOWN se ancla, no se desliza** (tanda 3): tres golpes de derecha a izquierda, uno por
  pantalla, con la ventana de la línea MÁS el hueco hasta la siguiente y nunca menos de 2.5 s.
  El avance sale de `crtIownProgress()` (contra la ventana del pedazo), no de `crtProgress()`,
  que llega a 1 en `t1` y apagaría la palabra antes de la última pantalla.
- **Un anillo del túnel es un BORDE fino, no una meseta**, y la densidad va con él: con el perfil
  fino y los 2.5 anillos de antes (`0.42/r`) queda un campo negro con dos aros. Van `2.0/r` y
  fondo casi negro entre anillos. El anillo que enciende el golpe no se mueve a mano: un valor
  fijo de `depth` se abre solo mientras `t` crece.
- **El QRS del `ekg` tiene PISO** (45 % de la escala). Con la altura saliendo sólo del parpadeo
  del tubo, un tema bajo dibujaba latidos de dos píxeles.
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
- **El estilo de entrada NO se elige adentro de `crtShotFor`** (que no puede leer nada vivo), pero
  tampoco en `Crt.qml`: si fuera un binding que mira el audio, cambiaría a mitad de verso. Se
  calcula una vez por línea en `show()`, **antes de `crtSerial++`** — Crt.qml lo lee al recibir la
  línea y para entonces ya tiene que estar puesto.
- **El "estilo anterior" se anota sólo para las pantallas que mostraron la línea.** Anotando
  también las vacías, "el anterior" deja de ser el que se vio y la regla de no repetir no dice
  nada. Lo que sí se acumula entre líneas es el registro (`crtLastEntry` se mergea, no se pisa).
- **`onLandedChanged` no se dispara con el valor inicial del delegate.** Por eso el contador del
  `overburn` sin `words` arranca en 0 y no en 1: con 1, la palabra 0 nace ya encendida y no se
  quema nunca. Y lleva paracaídas (`reveal >= 1`): si el compás se pierde a mitad de línea
  (`bpmLive` vence a los 15 s) los tiempos dejan de llegar y las palabras que faltan no aparecerían
  más. El contador se resetea también al cambiar `myText`, no sólo con el serial: en un relay el
  pedazo de la segunda pantalla arranca tiempos después de la línea.
- **En el QML la perilla `section_zoom` se llama `crtSectionZoom`** y multiplica al `camZoom` y al
  `cueZoom` en el mismo `Scale`: es otro plano de la misma cámara, no una cámara nueva. Desde la
  tanda 4 ese plano DESCANSA EN 1 y sólo el drop lo empuja un momento (`sectionKick`): un zoom
  sostenido por sección es lo que Ferox leyó como "está todo agrandado por default".
- **Un motivo no puede sacar el "drop" de `energy`.** Lo que le llega a `Motif` ya viene
  multiplicado por el aviso del salto (×1.25 en la pantalla destino, y sólo en los versos que
  cambian de foco con más de 2 s por delante; era ×1.6 en CADA verso hasta la tanda 4): un
  umbral ahí levanta la arena de `dunes` en cualquier estrofa. El drop viaja como booleano
  propio (`crt.ctl.audSection === "drop"`).
- **El dibujo de una pantalla es ESTADO, no una función pura.** Hasta la tanda 4 `crtMotifFor`
  se re-evaluaba sola por cinco caminos (el reloj de 25 s, cada `sec`, cada `cue`, la palabra
  clave de cada línea y cualquier cambio del pool, que movía `pick % pool.length` en las TRES
  pantallas juntas): 89 cambios de dibujo en 90 s, uno por verso y por pantalla. Ahora
  `crtMotifRefresh()` reparte sólo lo que venció el hold, excluyendo los kinds vigentes en las
  otras (que es cómo sobrevive la invariante de que dos pantallas apagadas nunca muestran lo
  mismo). Sólo el tema nuevo y el drop reparten todo junto.
- **La semilla del motivo se siembra al ASIGNARLO, no con `motifGen`.** Con el hold puesto, ese
  reloj sigue corriendo debajo de un dibujo que se queda, y el paisaje de `dunes` se re-sembraba
  solo cada 25 segundos — que es exactamente "cambia sin razón".
- **El puente entre dos dibujos NO va por `dim`.** `dim` tiene un `Behavior` de 220 ms, así que
  el cambio de `kind` caería con el dibujo viejo todavía a media luz. Va por `swap`, una property
  sin `Behavior`: lo que se ve es exactamente la curva que manda `Crt.qml`.
- **El portero del cambio de canal está en el CONSUMO, no en el sorteo.** El sorteo vive en
  `crtShotFor`, que no puede leer nada vivo (se evalúa sobre una línea que todavía no llegó y
  tiene que dar lo mismo cuando llega). El "no dos veces en menos de 20 s" lo pone `show()`
  (`crtChanFire`), que es lo único que sabe cuánto hace. El cambio de PARTE también lo dispara:
  ahí el glitch es el puente.
- **Donde estaba el aro, el verso NO rompe.** El aro pega su `hit(0.5)` con la raya ~100 ms
  después de la hora, y la patada del cambio de verso caería justo encima: dos roturas en la
  misma pantalla con 100 ms de diferencia no se leen como un golpe, se leen como una falla. El
  root anota en `crtRingWas` dónde estaba el aro ANTES de pisar la línea vieja (el mismo dato
  que ya usaba `crtEntriesFor`) y la pantalla que era el aro se saltea su `hit`.
- **`resetFaces()` en el pico tiene que mirar `color_hold`.** El comentario decía "un par de
  veces por canción" desde la tanda 2, pero el pico no tenía portero ninguno: con un pico cada
  12 s la pared se daba vuelta entera cinco veces por minuto.
- **El rayo del salto NO toca la pantalla del medio** (tanda 4, al revés de la 3). Le pegaba un
  `hit(0.25)` y la crominancia por 4 al pasar por su borde, y eso es lo que Ferox veía como "el
  rayo pasa por encima de las animaciones" — el rayo va por el borde justamente para no tocar
  ese motif. El modo `hop = interference` no desapareció: pasó a ser el remate de la LLEGADA
  (120 ms de crominancia cuando la cabeza converge, encima de la letra que entra), y por eso va
  sin `hit()`: es el mismo evento, no uno nuevo.
- **`crtHopMs` sale de `Motion.enterMs + 40`.** `show()` publica el arranque del salto y sube el
  serial en el mismo milisegundo, así que la letra y el rayo arrancan juntos; medido en el log
  (`crt: hop land`), la cabeza converge a los 367–388 ms y la palabra termina de asentarse a los
  320. El rayo aterriza sobre la frase ya puesta, que es el enganche. El salto de una pantalla
  dura la MITAD (`Motion.enterMs / 2 + 40`, medido 202–228 ms): recorre la mitad del camino, y
  con la misma duración iría a media velocidad y no se leería como el mismo objeto. Ahí aterriza
  con la palabra todavía asentándose, pero a los 200 ms la `OutExpo` de la entrada ya recorrió el
  99 %.
- **`hopAnchors()` se mapea contra `stage`, no contra `crt`.** `crt` es el `PanelWindow`, no un
  Item: `mapToItem(crt, …)` tira "Could not convert argument 0 … to const QQuickItem*" y devuelve
  undefined, así que las hebras del rayo salían siempre del fallback centrado — el efecto que la
  tanda 3 quería sacar, con el warning tapado porque el salto largo era raro. Y va con
  `Qt.point()`: la forma de tres argumentos también falla.
- **La cámara NUNCA se aleja por debajo de 1, y por eso no hay overscan** (tanda 4). Los cuatro
  factores del `Scale` de `camera` (`camZoom`, `cueZoom`, el latido y el plano de la sección) valen
  1 o más, así que un dibujo del tamaño del stage no puede dejar un marco de fondo plano alrededor.
  Cada motivo se dibuja al TAMAÑO DE LA PANTALLA, dentro de `motifFrame` (`Crt.qml`), que es un
  item `clip: true` que llena el padre; las barras del standby van en la misma caja. Hasta la tanda
  3 ese marco venía agrandado por `crt.overscan` (= 1.02/zoomMin) para tapar el plano de la estrofa
  (0.85), y el precio era que las dieciséis animaciones salían un 22 % más grandes y recortadas.
  **Si alguna vez un plano vuelve a bajar de 1, vuelve el marco: la solución es el plano, no el
  overscan.** Un motivo nuevo se prueba con `camera` al tope y la sección en `drop`.
- **Safe area: nada se dibuja hasta el canto.** Toda figura tiene que terminar dentro del 92 % del
  cuadro (4 % de aire por lado), medido con el ANCHO Y EL ALTO de esa pantalla, no con un radio
  fijo: la mancha (`rorschach.frag`) y la lámpara (`plasma.frag`) se salían por arriba porque su
  caída estaba clavada en 0.62 / 0.78 de un espacio corregido por aspecto, o sea más de medio alto.
  El arreglo va en la GEOMETRÍA (normalizar el dominio, o medir contra los semiejes de la pantalla),
  nunca escalando la imagen terminada: en un shader de ruido la silueta ES la textura.
- **La letra tiene su propio plano, `textPlane`, y vale 0.85.** Es el plano que le daba la estrofa
  antes de la tanda 4: sacarlo de la cámara sin dárselo a la letra la dejaba un 18 % más grande que
  en `a85fefc`. Va como `Scale` sobre el item `lyric` (y sobre el verso quemado), NO como factor
  sobre `font.pixelSize`: el tamaño lo deciden el tope en píxeles y la caja del `Text.Fit`, y
  tocando sólo el tope una línea larga —limitada por la caja— no cambiaría de tamaño.
- **El motivo lo elige UN solo `Loader`, no un `visible` por dibujo.** Con dieciséis
  interruptores independientes alcanza que uno quede prendido para que se vean dos motivos
  encima (así apareció el agua sin recortar sobre otra animación). `sourceComponent` es una
  property sola: dos no pueden estar vivos ni por un cuadro. No reintroducir un `visible` ni un
  `active` por motivo, y no sacarle el `clip` al Loader.
- **Un `Behavior` sobre una property que se recalcula sola no es una transición: es un filtro.**
  El encuadre era `camZoom` con un `Behavior` de 520 ms, y `pump` lo reescribe cada 70 ms: cada
  muestra de audio reiniciaba el tween, así que al recibir la línea la pantalla tardaba ~300 ms
  en llegar a su plano y la frase se veía nacer chica. Ahora son dos sumandos, `camFocus`
  (instantáneo, la línea nace con su tamaño) y `camBreath` (`pump` ya viene suavizado a 90 ms).
  (El latido conserva un tween corto propio, 260 ms: reiniciarlo con cada muestra está bien
  para una señal chica, era el PLANO el que se quedaba a mitad de camino.) El plano de la
  sección va por un `NumberAnimation` propio y no por `Behavior`, y se rearma cuando se va la
  estática del cambio de canal — eso último es **por las dudas**: la causa medida del salto
  seco es la de arriba, y el salto de la sección no se pudo reproducir sin ver la pantalla.
- **Una deriva fija en el espacio con aspecto NO es una fracción fija del cuadro.** El centro
  del túnel derivaba 0.08 en un espacio donde la x va multiplicada por `ar`: en la pantalla
  vertical (`ar` ≈ 0.56) medio ancho vale 0.28 y esos 0.08 eran casi un tercio, así que la boca
  se iba del encuadre. Va medida contra `vec2(0.5*ar, 0.5)` y clampeada al 15 %.
- **`fatal restart` deja el CRT APAGADO.** El interruptor es el archivo de `$XDG_RUNTIME_DIR` y
  el `stop` lo borra: después de cualquier restart hay que volver a `fatal crt on` si estaba
  prendido. Es la trampa de cualquier verificación en vivo.
- **El filtro `motifAllowed` NO mira qué pantalla pregunta.** `crtMotifFor` garantiza que dos
  pantallas apagadas nunca muestren el mismo dibujo repartiendo UNA lista entre todas; una lista
  distinta por pantalla rompe justo eso. Por eso `eyes` se descarta cuando no hay letra o hay una
  sola pantalla, y no cuando "esta pantalla es la enfocada" (la enfocada muestra texto y no dibuja
  ningún motivo).
- **El número de verso no sale del `serial`.** `crtSerial` es un contador de la sesión: después de
  un rebobinado, o entrando a mitad de tema, no dice en qué línea va. `crtLineNo` lo busca por
  `t0` contra la letra entera (tolerancia 0.05 s: el daemon manda los tiempos redondeados a dos
  decimales), y devuelve -1 si la letra no está sincronizada, porque ahí todas las líneas
  arrancan en cero y la primera matchearía siempre.
- **La letra sin sincronizar ahora TAMBIÉN viaja al overlay** (`lyrics_plain`, con
  `synced: false`). Sin el campo `synced` no se distingue de una letra sincronizada que arranca en
  cero. Es lo que hace correr `textsea` en un tema sin tiempos, sin resaltar nada.
- **La máscara de `static` se esconde con `hideSource`, nunca con `visible: false`** — adentro de
  un item invisible no se dibuja nada y la captura sale vacía (la misma trampa que el burn-in de
  los carteles). Y lo que se va a formar se congela al arrancar la convergencia: `crtNext` cambia
  cuando cae la línea siguiente y la palabra mutaría a mitad de camino.
- **Una velocidad NO se multiplica por el reloj: se acumula.** El túnel, el hiperespacio y el
  giro del osciloscopio llevan su propia distancia recorrida, sumada cuadro a cuadro con la
  velocidad del momento. Con `posición = reloj × velocidad`, el reloj vale miles de segundos y
  cualquier cambio de velocidad (el drop es el más grande) se multiplica entero: todo se
  teletransporta de una. Es la razón por la que el `tunnel` de una pasada vieja se veía mal.
- **Un motivo no se puede apagar atándole el `visible` a `running`.** El `tunnel` anterior se
  sacó por quedar EN BLANCO: con la pantalla quieta tiene que dibujar el cuadro completo, sin
  avanzar. Lo mismo el cardiograma, que además necesita un `requestPaint()` en
  `Component.onCompleted` y en `onVisibleChanged` — con el Timer parado no lo llama nadie.
- **El QRS del `ekg` sale del `tick`, no del `beat`.** `beat` son onsets crudos: con ese, el
  latido cae donde el bombo pega fuerte y no donde va el tiempo. `tick` ya está cuantizado al
  compás. Sin compás confiable no hay más remedio que el crudo.
- **En GLSL ES 100 el tope de un `for` tiene que ser constante.** El `plasma` recorre siempre
  seis bolas y las que sobran (pantalla lenta) pesan cero por `step()`, en vez de recortar el
  loop. Y todo `1/r²` va con `max(dot(d,d), ε)`: sin eso, el centro de una bola es un NaN y el
  NaN es un agujero en la imagen.
- **Un `ShaderEffectSource` con `live: true` re-renderiza su fuente en CADA cuadro.** La
  máscara de `static` cambia una vez por compás: va `live: false` con `scheduleUpdate()` a mano
  en `converge()`, en el cambio de tamaño y al nacer. Sin el de nacer no hay textura ninguna.
- **`mock.patch.dict` COPIA los valores:** mutar el dict que se le pasó no toca `config.CFG`. Un
  test que apagaba `sing` así dejó la captura girando para siempre y colgó la suite entera.

## Números medidos

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
- CRT prendido: **20-37% de un core** (media 29 sobre ocho muestras de 8 s, tres monitores,
  motivos de shader en las laterales). Era ~19% antes del overscan de la tanda 3: la cámara
  aleja el cuadro hasta 0.82 y esos píxeles ANTES no se dibujaban — que es exactamente lo que
  se veía como un marco de color plano. El área de más es 1/0.82² ≈ 1.5×, así que el número
  sube por construcción, no por un desperdicio que se pueda sacar. Apagado: 1.7% (sin captura,
  sin texturas).
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
- **CPU del overlay: falta re-medir en silencio.** El baseline de la corrida 3 de la tanda 4
  (31.6 % de un core, ocho muestras) se tomó con el player en pausa; cuando estuvo el techo de
  cuadros de los motivos ya había música sonando, y el A/B en esas condiciones (wild 42 % /
  normal 52 %, con muestras de 29 a 68 %) es ruido. `docs/plans/cpu-bench.py`, con Spotify
  parado.
- README: falta la captura del menú de bandeja y la de `fatal config`. Receta del GIF:
  `wf-recorder -o <salida>` + ffmpeg `palettegen(max_colors=96)` / `paletteuse`. No hay gifsicle.
- **La tanda 3 quedó COMPLETA** (`docs/plans/2026-09-04-crt-tanda3-feedback.md`): la corrida 1
  fue A1 (el overscan de los motivos), A2 (un `Loader` solo), A3 (el encuadre y el plano de la
  sección), A4 (la boca del túnel) y B7; la 2 fue A5 (una animación por pantalla), B1 (el aro que
  se desarma), B10 (el aro que come al ritmo), B2 (las familias de la mancha), B3 (los ojos),
  B4 (el rayo del salto), B8 (el contraste del túnel), B9 (el piso del cardiograma), B5 (el IOWN
  anclado) y B6 (el piso de 120 ms); la 3 fue C (el sync a ojo: la regla por temas, el rótulo
  del tubo, `fatal sync show|reset` y las perillas `[keys]`). Lo que se miró con capturas y lo
  que todavía necesita un ojo está en `docs/plans/CHECKS-VISUALES.md`, secciones "TANDA 3
  corrida 1", "corrida 2" y "corrida 3".
- **El plan `docs/plans/2026-09-03-crt-tanda2.md` quedó COMPLETO** (FASE 0 a FASE 5): foco
  anticipado, aviso de destino (`foreshadow`/`ring`), saltos entre pantallas (`hop`), entradas
  nuevas + director por energía, y ocho motifs nuevos. Estado y mapa actualizado en
  `docs/plans/2026-09-03-estado-tras-tanda2.md`; lo que falta mirar a ojo está en
  `docs/plans/CHECKS-VISUALES.md` (nadie lo vio prendido con música todavía).
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
