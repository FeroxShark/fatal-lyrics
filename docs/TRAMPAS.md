# cartelitos — Trampas

Bugs que ya pasaron y por qué. Antes de diagnosticar algo raro, buscá acá. Cada trampa nueva va acá, no a `CLAUDE.md`.
Movido tal cual desde `CLAUDE.md` el 2026-09-05.

- **El forzado de motif va por un `cmd` propio (`motif`), no por una perilla de `config`.** El
  daemon reenvía el evento `config` ENTERO en cada reconexión y `applyConfig` llama a
  `crtForget()`: un forzado que viajara ahí se apagaría solo y de paso movería el reparto de la
  línea. Y del lado del dibujo son TRES `visible` y no uno: `motifFrame` (que sin el forzado sólo
  se dibuja sin letra), `standbyLayer` (declarado DESPUÉS: sin apagarlo, con el player parado la
  captura sale "NO SIGNAL" en vez del dibujo) y el `z` del motivo (declarado después del verso:
  sin bajarlo tapa justo la letra que se quería ver encima).
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
- **Un dibujo que se mide contra el ALTO sale de dos tamaños distintos en la pared.** DP-4 es
  vertical, así que `height` vale 1920 donde en las otras dos vale 1080: el mismo trazo salía de
  13 px en la apaisada y de 23 en la vertical (`ekg`), y la misma letra de 22 y de 38
  (`textsea`). Todo grosor, todo cuerpo de letra y toda caja se miden con `Math.min(w, h)`. Lo
  que SÍ se mide con el ancho y el alto por separado es el aire contra el borde (4 % de cada
  uno), que es una fracción del cuadro y no un tamaño.
- **Una retícula proyectada se muestrea geométrica en Z y CONSTANTE en X.** En `dunes`, con paso
  constante en Z las filas lejanas caen todas en el mismo píxel (el escalón sobre el horizonte);
  con el paso horizontal escalado por Z para que los granos guarden su separación EN PANTALLA,
  desaparece el punto de fuga y quedan columnas verticales perfectas con cinco granos por fila
  en la vertical. La perspectiva de verdad es que las filas de atrás tengan MÁS granos.
- **Un horizonte no se dibuja: se deja de dibujar.** El `glow` de dos exponenciales en `|dy|` es
  una raya encendida, y una raya encendida en el medio del cuadro es lo que Ferox vio partiendo
  la imagen. Va una niebla que sigue por debajo del horizonte y se apaga con `smoothstep`, cuya
  derivada es cero en el cruce: sin derivada no hay canto.
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
  fondo casi negro entre anillos. Desde la tanda 5 la pared además va en DOVELAS (una hilada por
  anillo, aparejo a soga, un tono por ladrillo): anillos concéntricos sobre un piso liso son
  aros, no un túnel.
- **La curva del túnel es una PROYECCIÓN, no un offset.** El eje del tubo se aparta con la
  profundidad y en pantalla eso vale una fracción del radio de ESE anillo (`c = r·C/2`), así la
  boca se queda quieta y el fondo camina. Escrito de la forma obvia — un offset en función de la
  profundidad — el mapa se PLIEGA y salen garras encima de los anillos del medio: `d(dz)/dr` es
  `-dz²/2`, cientos cerca del centro, y el offset deja de ser menor que el radio. Por lo mismo,
  resolver `p = q - c(depth(p))` iterando no converge. El techo es `|C| < 2`, y lo que pliega es
  el PRODUCTO de la amplitud por la frecuencia: subir una obliga a bajar la otra.
- **El túnel se compone por alpha como todos los motivos, y por eso en las caras de paleta
  invertida el fondo del pozo es CLARO.** Las dos alternativas están probadas y son peores
  (documentadas adentro de `tunnel.frag`): pintar el fondo negro opaco tira el negro ENCIMA de
  las dovelas y aplana la pared, y dibujar todo casi opaco sobre un fondo propio deja la cara
  invertida como una losa oscura. Mismo trato que el cielo de `ocean`.
- **La velocidad del túnel no puede leer `energy`.** La energía llega ×1.25 en la pantalla a la
  que va a saltar la frase: atada ahí, el túnel pegaba un tirón cada vez que estaba por caer una
  línea. Velocidad constante, ±3 % de volumen, y el único que la cambia es el drop.
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
- **`fatal restart` rota `qs.log` a `qs.log.1` en cada arranque** (tanda 6 corrida 6, `rotate_log`
  en `bin/fatal`; antes rotaba sólo pasados los 5 MB, y un log de pocos KB con warnings de diez
  restarts viejos nunca llegaba a ese tamaño — un warning de una sesión vieja, o de un `shell.qml`
  a medio editar que se hot-recargó, sobrevivía al restart y se leía como si fuera de ahora, con
  números de línea de un archivo que ya no existe. Así se cayó el "bug" de los 44 `TypeError:
  crtMotifRefresh is not a function` de la tanda 4: eran del hot-reload roto de la corrida 3, no
  de HEAD). No hace falta truncar a mano antes de auditar: cada `fatal restart` ya arranca con
  `qs.log` vacío.
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
  se iba del encuadre. Desde la tanda 5 el túnel no tiene ese espacio: normaliza por `min(w, h)`
  —el lado corto va de -0.5 a 0.5 y el largo desborda—, que es lo que hace que un anillo mida lo
  mismo en la vertical y en las apaisadas. Escalar la x por el aspecto ES normalizar por el
  ALTO; en DP-4 el radio de esquina valía 0.57 contra 1.02 de las otras dos.
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
- **En GLSL ES 100 el tope de un `for` tiene que ser constante.** El `plasma` no tiene loop:
  evalúa las seis bolas DESENROLLADAS y las que la pantalla lenta no usa llegan con radio cero,
  que pesa cero. Y todo `1/r²` va con `max(dot(d,d), ε)`: sin eso, el centro de una bola es un
  NaN y el NaN es un agujero en la imagen.
- **La burbuja del `plasma` es física de QML, no senos del shader** (tanda 4b). Las seis bolas
  viajan como `vec4(x, y, radio, ángulo)`: la posición la calcula un resorte amortiguado en
  `Plasma.qml` a 60 Hz, porque un seno no tiene inercia y no hay golpe que lo empuje ni que lo
  devuelva — eso era la elipse quieta que Ferox vio. Cuatro cosas que no se tocan: (1) las
  posiciones van en unidades de `rmin` y se reparten sobre el ÓVALO de la pantalla
  (`axX`/`axY`), no sobre un círculo, así en la vertical se separan para arriba y para abajo,
  que es donde hay lugar, y las gotas siguen valiendo lo mismo en las tres pantallas; (2) la
  dirección del estirón viaja como ÁNGULO (`b.w`) y no como `normalize(xy)`, que en reposo —con
  todas las bolas encima del centro— es una división por nada; (3) el safe area lo garantiza el
  óvalo del shader (`smoothstep(1.0, 0.78, length(p/glass))`), NO el clamp de QML: el clamp
  acota UNA bola y la superficie de tres fundidas llega más lejos que cualquiera de ellas; (4)
  los empujones entran por CONTADOR (`beat`, `kick`) y nunca por magnitud — `if (surge > 0.9)`
  se cumple ~24 ms, o sea dos cuadros a 60 Hz y cinco en el monitor de 200.
- **Un `ShaderEffectSource` con `live: true` re-renderiza su fuente en CADA cuadro.** La
  máscara de `static` cambia una vez por compás: va `live: false` con `scheduleUpdate()` a mano
  en `converge()`, en el cambio de tamaño y al nacer. Sin el de nacer no hay textura ninguna.
- **`mock.patch.dict` COPIA los valores:** mutar el dict que se le pasó no toca `config.CFG`. Un
  test que apagaba `sing` así dejó la captura girando para siempre y colgó la suite entera.
- **La recuperación automática de `crtQuality` no puede subir por encima del techo que Ferox
  configuró.** El modo degradado por GPU (T0.12, `Crt.qml`) baja `crtQuality` a 0.75 solo y la
  sube sola con histéresis (28 s de frames sanos). La primera versión subía siempre a `1`, a
  pelo: si Ferox pone `crt_quality = 0.75` en el TOML a propósito (GPU floja), la recuperación se
  lo pisaba en el primer respiro de CPU. Arreglado con `crtQualityCeiling` (`shell.qml`): lo que
  pone el TOML, separado del valor EN VIVO que sube y baja; la recuperación siempre apunta al
  techo, nunca a `1` fijo. Probarlo "forzando `crt_quality = 0.75` por config" y mirando que no
  suba es la trampa: eso fuerza el TECHO, no dispara el modo degradado (que sólo se activa con
  frame time real sostenido). Para probar la baja/recuperación de verdad hace falta carga real de
  GPU (`docs/plans/cpu-bench.py` o similar) con el daemon corriendo.
- **El volumen del sink no siempre llega a lo que graba `pw-record`.** Para normalizar `mood.energy()`
  por volumen (`docs/PENDIENTES.md`: "Mood sesgado por volumen") hacía falta saber si el sink
  entra en la ganancia efectiva. MEDIDO con un tono generado y `paplay`/`pw-record --target=<id>`:
  en un sink `HW_VOLUME_CTRL` (el auricular USB de Ferox) subir/bajar el volumen del SINK del 100%
  al 30% no mueve el rms capturado casi nada (0.410 contra 0.407) — el fader es de hardware y
  queda DESPUÉS de donde `pw-record` engancha el monitor. El volumen del STREAM de la app sí
  entra (100% a 30% de stream: 0.420 a 0.011 de rms, proporción 0.027 ≈ 0.30³, la escala cúbica de
  siempre) porque ese es software y se mezcla antes. Por eso `_capture_gain()`
  (`cartelitos/audio.py`) sólo multiplica el volumen del sink si `sink_has_hw_volume()` dice que
  NO es de hardware; si es de hardware, cuenta sólo el stream. Y la escala cúbica no es sólo cosa
  de `wpctl`: `pactl` muestra el mismo cubo, tanto para el sink como para el sink-input (76% de
  sink → -7.15dB = 20·log10(0.76³); 40% de stream → -23.89dB = 20·log10(0.40³)).
- **El tubo son dos pasadas y los `ShaderEffectSource` van con `smooth: false`** (tanda 7,
  corrida 1). `stage` → `stageTex` → `signalPass` (`signal.frag`) → `signalTex` → `glass`
  (`crt.frag`). El `layer` de antes muestreaba sin filtro; un `ShaderEffectSource` viene con
  `smooth: true`, y con eso los bordes del glifo cambian aunque `composite = 0` sea un
  passthrough. Los dos van a la misma resolución (texel a texel) o el passthrough deja de serlo.
  `stage.opacity` (el oscurecido del karaoke) se movió a `glass.opacity`: si no, el shader del
  vidrio le sumaría estática a una señal ya apagada.
- **Comparar capturas del tubo de a píxel exige congelar `t` y esperar ≥ 6 s.** `crt.frag` y
  `signal.frag` leen `crt.tubeTime`: para un antes/después se parchea temporalmente
  `property real t: 1.234` en las dos ShaderEffect, se manda un `show` con `t1` largo (12 s) y se
  captura recién a los 6 s (la entrada de la línea todavía se asienta a los ~3.5 s). El primer
  `show` tras un restart cae en el intro (estática o un motif): calentar con uno de descarte.
  Ruido viejo contra viejo: máx. 1/255; el passthrough contra el viejo: máx. 3/255 en ~60
  píxeles de borde de glifo (empate de redondeo del muestreo).
- **La estela (`crt.persistence`, tanda 7 corrida 3) y sus siete trampas.**
  1. **El `dt` NO sale del reloj de animaciones.** Un `ShaderEffectSource` `live` + `recursive`
     se vuelve a dibujar en cada cuadro de SU ventana (medido: DP-5 144/s, HDMI-A-2 120/s, DP-4
     60/s) pero el driver de QML marca 16 ms en las tres. Con `FrameAnimation` la estela decaía
     3 veces más rápido en las pantallas rápidas. `trailDt` sale de `frameSwapped` de cada ventana.
  2. **Un `.qsb` no se recarga en caliente** (el QML sí): tras tocar `signal.frag` hace falta
     `fatal restart`, o se mide un shader viejo y la estela "no existe".
  3. **El auto-drop de calidad apaga la estela** (`trailOn` pide `crtQuality >= 1`): cualquier
     `grim`/`wf-recorder` en las tres pantallas baja el tubo (frame > 28 ms por 3 s). Capturar de a
     un monitor y mandar `crt_quality` 0.999 antes (un cambio del techo resetea `crtQuality`).
  4. **Cara clara: la tinta es oscura.** El piso lineal y el `max` se invierten (`light`) y la
     pantalla clara cambia de verso con estática/rotura, así que no mide nada. Para medir hay que
     mover el monitor a una cara oscura con `crt_order` (`persist-drive.py` prueba permutaciones).
  5. **El residuo en RGBA8** de `prev*decay` se clava en 1/255 si no hay piso lineal: por eso
     `lin`, y por eso los tests simulan el redondeo de 8 bits.
  6. **Un monitor vertical (DP-5, 1080x1920)** dio una caja de 230x1874 y `persist-drive.py`
     se quedó sin memoria: la caja va tope en 240 px.
  7. **wf-recorder graba VFR:** `ffmpeg -fps_mode passthrough` y los `pts` de `ffprobe`
     (`frame=pts_time`, con coma final); sin eso ffmpeg duplica cuadros hasta la cadencia fija.

## Autostart: un solo `exec-once`

Hubo dos `exec-once` compitiendo: el de `hyprland.conf` arrancaba en t=0 sin monitores y el de
`execs.conf` veía sus pidfiles y hacía no-op → boot roto. Queda UNO solo, en `execs.conf`, con
`sleep 6 && cartelitos restart`. No reintroducir un segundo.

## Drivers de la tensión: el `clear` del daemon y el reinicio

- Con el reproductor pausado el daemon manda `clear` (why=track) a los ~15 s ("long pause:
  dialogs cleared"): el overlay pierde `crtLines`, el Timer de `crt: tension` (que exige
  `crtLines.length > 0`) deja de loguear y la curva se trunca. `chorus-drive.py` reenvía el
  evento `lyrics` cada 2 s por eso. Cualquier driver que pause el player tiene que hacer lo mismo.
- `fatal restart` deja el CRT apagado (el archivo `cartelitos-crt` se resetea): un driver que
  reinicia para releer el log tiene que volver a hacer `fatal crt on`.

## Detalle movido desde CLAUDE.md (intro, palabras, raros)

- **Intro (`crt.intro`):** `clear` (why="track") apaga toda la pared, `tubeOffMs` después la
  prende con el DEGAUSS (fase `degauss`, `Motion.degaussMs` 700: uniform `degauss` de `crt.frag`,
  onda radial + anillos de pureza + destello; `Crt.qml` la anima 1→0 y NO corre el haz de `tubeon`
  en esa fase: el reencendido es UN movimiento; la fase se pone ANTES de `crtSetDark(-1,false)`
  justamente para eso; la estática ya se dibuja debajo, es lo que la onda ondula), `introStaticMs` (300)
  después la tarjeta (`crt.intro_card`: `testcard` = el dibujo del motivo `testcard` de `Motif.qml`
  con `title`=título en la banda de identificación e `info`=artista bajo el círculo, en un Loader
  que sólo existe mientras se ve; `plain` = título grande y artista de antes; fuente y esquema del
  set) en la pantalla del próximo foco. Si el verso llega en pleno degauss, `crtIntroSkip` y la
  onda se apaga con `exitMs` (`degaussCutAnim`), no de un corte. La tarjeta NO tiene plazo propio: se queda
  puesta (intro instrumental, "el título acompaña") hasta que `show()` la corta — de un golpe si
  el primer verso llega antes de la tarjeta (`crtIntroSkip`) o cortándola si ya estaba puesta
  (`crtIntroEnd`, `Crt.qml` la anima afuera con `Motion.exitMs`, nunca un corte seco). Si el
  `np` nunca llega, sólo estática (`introStaticMs`) y sigue sin tarjeta. Mientras `crtIntroOn` los
  handlers de `sec`/`cue` no tocan canal, escena ni motivo (se aplican una sola vez al terminar).
- **Palabras (`wholeWordsOn`):** es `allMode && layout !== "split" && crtQuality >= 1`; cuesta 4.4
  puntos de CPU (`docs/NUMEROS-MEDIDOS.md`; en director reparte por largo). `emphasisGateOpen`
  suprime el pulso dentro de `Motion.enterMs` de la entrada. El auto-drop de calidad
  (`FrameAnimation`, frame > 28 ms por 3 s → `crtQuality` 0.75; sube tras 28 s) lo apaga.
- **Raros (`crt.rare`):** `bsod` es una pantalla azul de cero en `Crt.qml` (nada del modo Win95,
  fondo `#0000aa`, el verso en la fuente del set), `nosignal` reusa `standbyLayer` (3 s, vuelve
  sola) y `testcard` fuerza el motivo `testcard` 6 s. `motifs.py` (`parse_rare`) los fuerza por
  socket.

## El quemado del estribillo (tanda 7, corrida 4b)

- **Quickshell se cae (SIGSEGV en `QQuickItem::addToDirtyList`) al apagar/prender el CRT si hay un
  `Behavior`/animación sobre una propiedad que llega a un uniform de un ShaderEffect, o si los items
  del quemado (`burnPass`/`burnTex`, recursivo) existen siempre.** Con un `Behavior` por ventana: 6/6
  caídas en `fatal crt off`. Con los items siempre presentes: ~1 de cada 10 ciclos on/off (0 de 45 sin
  ellos). Hoy: el fade es una cuenta sobre `posAbs`, los items viven en un `Loader` (`active:
  burnHave`) y se destruyen con `burnWipe()` (cambio de tema Y `crtOn` en false). 40/40 ciclos on/off
  sin quemado, 6/6 con quemado armado. Validado en la corrida 5a con `docs/plans/cycle-drive.py`
  (quemado armado con `crt: burn k>=2` en CADA ciclo, carga externa 3–14): 0 caídas en 43 ciclos
  on/off y 0 en 32 con un `clear why=track` en el medio (el PID del overlay no cambió y `coredumpctl`
  no sumó ningún SIGSEGV). Diagnóstico: `coredumpctl info <pid>`; el que sale primero en la
  lista suele ser el REPORTER del crash handler, no el proceso (mirar `Command Line`/timestamp).
- **Cambio de calidad: SIGSEGV dentro del driver nvidia, en `QRhi::beginFrame` (corrida 6, 2 casos;
  arreglado en corrida 6b, sin reproducir a demanda).** Firma distinta a la de arriba: pila
  `libnvidia-eglcore.so` (#4-#6) ← `libQt6Gui` (#7-#8) ← `QRhi::beginFrame` ← `QQuickWindow::event`
  (UpdateRequest), sin ningún frame de Quickshell/QML ni `addToDirtyList`. `beginFrame` de QRhiGles2 corre
  `executeDeferredReleases`: cae al liberar una textura/FBO vieja, o sea, algo que se destruyó o
  redimensionó el cuadro anterior. Los dos casos (00:06 tras cpu-bench, 00:12 en un `fatal crt off`
  posterior; `coredumpctl info <pid>`, `~/.cache/quickshell/crashes/<id>/log.qslog.log`) tienen la MISMA
  última línea de log: `crt: quality 0.75 -> 1 (frame sano 28s)` + `crt: trail N on` — el cambio de
  calidad redimensionaba `stageTex`/`signalTex` Y conmutaba `recursive` de `signalTex` en el mismo cuadro.
  Hoy va en dos tiempos (`texQuality`/`trailQ` + `qualityStepTimer`, `qualityStepMs` 150): al BAJAR la
  estela se apaga ya y la textura achica después; al SUBIR la textura crece ya y la estela vuelve después.
  Sin repro: `docs/plans/quality-drive.py` (`quality|intro|mixed`, alterna `crt_quality` 0.75/1.0 por config
  con esperas al azar, `clear why=track` durante el intro y `fatal crt off/on`) con el código VIEJO: 0
  caídas en 60 ciclos `quality` + 40 `mixed` + 80 `quality` con `cpu-bench techo` en paralelo (360
  cambios); con el fix: 0 en 60 `mixed`. Se dispara sólo con la GPU pisada (frames de 33 ms) y algo de
  suerte, así que "0 caídas" no prueba el arreglo: si vuelve, mirar primero qué más redimensiona un
  source (`burnTex` es de tamaño fijo) y probar liberar la textura con `visible: false` un cuadro antes.
- Medir contraste: UNA pasada, alternando sólo `crt_burnin` en vivo (`chorus-drive.py burn`); dos
  `clear` distintos re-siembran el set y cambian cara clara/oscura.

## Glitches en el tiempo (tanda 7, corrida 5a)

- **No soltar el glitch diferido con el `beatTick`.** Sale de un poll de 25 ms (más la carga de la
  máquina: 40–70 ms tarde con load 14) y, además, cada re-anclaje de la grilla (evento `bpm`, que
  llega seguido) cambia el índice de tiempo y dispara un `beatTick` de más en CUALQUIER momento:
  el pendiente salía fuera de tiempo. `hit()` calcula la marca contra `lastBeatAt` (`hitDueAt`).
- **El `Timer` de QML es grueso (`Qt::CoarseTimer`, ±5 % del intervalo).** Un solo `Timer` al
  tiempo caía 10 ms ANTES (en 500 ms, hasta 25 ms para cada lado). `beatStep()` se acerca en pasos
  del 85 % de lo que falta y sólo el último, de menos de 40 ms (donde Qt es preciso), llega a la marca.
- La barra que rueda usa `rollPhase` (QML, doble precisión, anclada a `lastBeatAt`), no `t` del
  shader: con `beat_lock = false` o sin compás vale `tubeTime * 0.085` = lo de siempre. Un salto de
  fase al re-anclar es esperable y no se ve (la barra vale 0.05 de tinte).
- Medir: `beat-drive.py` necesita el reproductor PAUSADO (si no, el daemon manda su propio `bpm` y
  pisa la grilla sintética). Un show cada múltiplo exacto de un tiempo no sirve: los glitches caen
  siempre en la misma fase (el control da un pico falso) — el driver usa 2.63 s.


## Efectos por palabra (tanda 7, corrida 5b, `crt.word_fx`)

- **Tabla:** `motifWords` es `{re, kind?, fx?}` (regex anclada `^..$`, es + en); `fx` = `alarm` (fuego, sangre,
  quemar: uniform `alarm` rojo vía `fxAlarmAmt`), `blink` (morir/muerte: `tubeLevel` a 0.12, largo), `glitch`
  (romper/caer: `hit(0.9)`) o `dark` (oscuro/apagar: `tubeLevel` a 0, corto). Los hold viven en `Motion.qml`
  (`fxAlarmHoldMs`/`fxBlinkHoldMs`/`fxDarkHoldMs`). Una sola vez por línea (`fxFired`, se rearma en `myText`
  y en `crtSerial`), la primera palabra clave del pedazo. Siempre `hit(…, urgent)` y `fxGapMs` (calm 12000,
  normal 6000, wild 0); si el portero `hitGap` se lo come el visual sale igual (log `hit=held`).
- **Con el director la frase se parte entre pantallas: el índice de `myWords` NO es el de la línea.** El
  tiempo de la palabra se busca en `crtLine.words` POR PALABRA (`crtWordKey`: sin puntuación, minúscula), no
  por índice. Con `f.t`, el efecto sale cuando `songPos() >= t` en el pedazo que tiene la palabra: si el
  pedazo llega tarde, sale al llegar (el lag medido contra el `show` es de ~1.4 s en el driver por eso).
- **No usar `emphasisGateOpen` para el disparo:** es un binding sobre `Date.now()` y sólo se reevalúa cuando
  `reveal` cambia; una línea quieta lo deja congelado en `false`. Se lee la condición directo
  (`Date.now() - textArrivedAt >= Motion.enterMs`).
- **Manejar con `fx-drive.py`:** el `show` NO debe traer `next` (el tubo consume el `next` a su `due` y pisa la
  línea de prueba) y hay que mandar `pos` cada ~100 ms (sin ellos `songPos` se clava a posAbs+1.5 s y el
  pedazo con la palabra, que arranca más tarde, nunca llega).
- **rollPhase:** con compás la vuelta dura el múltiplo de 4 tiempos más cercano a 1/`rollFreeRate` (0.085 laps/s
  ≈ 11.8 s; 6 compases a 120 bpm), fase desde la grilla absoluta `lastBeatAt mod beatMs`. No hardcodear.

## Detalle movido: motivos y set (desde CLAUDE.md)

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
  abran y estiren la burbuja —el golpe la parte en dos o tres gotas y el resorte las vuelve a
  fundir— y `tunnel` viaja a velocidad CONSTANTE (sólo el drop lo acelera) con una luz que
  corre pared adentro en cada tiempo. Y `scope`
  cierra la figura de Lissajous cuando el compás es confiable (la relación entre los ejes sale
  de la parte del tema); `stars` salta al hiperespacio en el drop.

- `crtSetFor(seed, mood)` (`shell.qml`) — el set por tema (perilla `crt.set`, tanda 6): 4 kinds
  de motif, una familia de entrada (`typed`/`hard`/`burn`/`soft`, tabla `crtEntryFamilies`), un
  scheme de color y una fuente, todo de una semilla atada a `crtTrackSeed` (se recalcula sólo al
  cambiar de tema). `crtMotifBag`/`crtEntryBag` — mazos barajados con `crtHash` (uno por
  pantalla) que reparten SIN repetir de los 4 kinds del set hasta agotarse y recién ahí
  rebarajan (`crt: bag refill [...]` en el log); se vacían en el `clear` de tema. Con
  `crt.set = "off"` vuelve el sorteo plano de siempre (`motifPool`/`crtEntryTable`). Una
  palabra clave de `motifWords` sigue pudiendo forzar un motif de afuera del set. El `mood`
  (corrida 3) mueve la cuota de `motifGroups` calm/hot/neutral y la familia de entrada según
  energy/valence — se congela una sola vez por tema en `crtMoodLocked` (primer verso), y no
  toca el esquema de color si la tapa ya lo puso (`crtPalette = "album"`).

## Capturas/medidas con NO SIGNAL encima: un overlay viejo del mismo repo (tanda 7, corrida 7)

- Síntoma: con el CRT prendido y `fatal crt motif scope --screen all`, el log decía `crt: scope lissajous` pero
  `grim` capturaba barras + NO SIGNAL en las tres pantallas, y el A/B de CPU medía dos overlays.
- Causa: quedó un `quickshell` de una sesión anterior (mismo cwd, otro pid, daemon viejo) y el flag del CRT
  es UN archivo compartido: ambos overlays prenden y el viejo, sin música ni forzado, pinta el standby por encima.
  `fatal restart` no lo mata.
- Cómo verlo: `hyprctl layers | grep cartelitos-crt` con el CRT prendido: debe haber UN solo pid por pantalla.
  Se cerró con `kill <pid>` del sobrante.

## Procesos huérfanos: dos overlays / dos daemons a la vez (tanda 7, corrida 7b, paso 0)

- **Síntoma:** medidas de CPU y capturas que no cierran, NO SIGNAL o un flag del CRT que "se pisa solo".
  El flag `cartelitos-crt` y el socket son UNO por sesión: cada overlay o daemon extra pelea por ellos.
- **Quiénes eran (2026-09-26):** dos `/usr/bin/quickshell` sin args (ppid 1, cwd en el repo) y dos
  `cartelitos.py`, uno de un worktree `/tmp/wt` ya borrado (`fatal on` desde un worktree levanta ESA copia:
  `BASE` sale de dónde vive el script). El `fatal restart` no los mataba: sólo conoce lo que está en el pidfile.
- **El respawn del crash handler de Quickshell SÍ aplica (0.3.1, `strings /usr/bin/quickshell`):** tras un
  SIGSEGV el proceso caído lanza un *reporter* (un `quickshell` sin args que abre el diálogo "Quickshell has
  crashed" y queda con ppid 1 hasta que alguien lo cierre) y, si el crash fue a más de 10 s de arrancar
  ("Quickshell has been restarted."), relanza el shell. El relanzado tiene otro PID que el de `qs.pid`, así que
  `fatal status` dice HALF/OFF y un `fatal restart` levantaba uno SEGUNDO. Los crashes de la tanda 7 (ver
  quemado y calidad más arriba) dejaron un reporter y un relanzado cada uno. Detalle de cada caída en
  `~/.cache/quickshell/crashes/<id>/`; `QS_DISABLE_CRASH_HANDLER=1` apagaría el respawn pero también el
  `report.txt`/`log.qslog.log` que usamos para diagnosticar: no se apagó.
- **Arreglo (guardia de instancia única):** el daemon toma un `flock` sobre `$XDG_RUNTIME_DIR/cartelitos/
  daemon.lock` (`util.acquire_instance_lock`, el segundo sale con "already running (pid N)", y anota su pid en
  el archivo); el overlay lo toma un wrapper `sh` de `bin/fatal` (`qs.lock`, fd 9) que anota SU pid y corre `qs`
  con `9>&-`: el fd NO se hereda. La primera versión lo dejaba pasar a los hijos (para que el relanzado del
  crash handler contara como instancia) y `fatal stop` con `fuser -k` se llevaba puesto cualquier proceso que
  qs lanzara — un navegador, un xdg-open —, aunque fuera una app de Ferox. Ahora el wrapper queda vivo mientras
  haya un `qs|quickshell` en su sesión (`setsid`: el relanzado y el reporter nacen ahí) y `stop` baja el pid del
  lock (confirmando el cmdline por NOMBRE de archivo, `shell.qml`/`cartelitos.py`: puede ser la copia de otro
  checkout) más esos `qs|quickshell` de la sesión — nunca por fd. Si el wrapper cae y quedan
  huérfanos, `on` los ve por el número de sesión (el wrapper ya no existe, así que el número no puede ser de
  otro). `fatal on/restart` con una instancia ajena rechaza con mensaje y NO pisa el pidfile. El kernel suelta el
  flock al morir el dueño: nunca hay lock viejo que limpiar. `qs.pid` guarda el pid de qs, no el del wrapper.
  Tests: `tests/test_guard.py` (incluye un bystander que no hereda el lock y sobrevive al `stop`).
- **Drivers:** ninguno de `docs/plans/*.py` levanta su propio daemon u overlay (todos hablan con `fatal`);
  los helpers que sí lanzan (`aud-feed.py`, `pw-play`) tienen que bajarse en un `finally`. Si un worker necesita una
  instancia aparte, tiene que ser con otro `XDG_RUNTIME_DIR` (otro lock, otro socket, otro flag).
- **Ver a mano:** `pgrep -af 'quickshell|cartelitos.py'` — tiene que haber un overlay y un daemon (más, a lo
  sumo, `/usr/bin/quickshell` de otras cosas de Ferox que NO abren `shell.qml`).
