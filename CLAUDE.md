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

- `bin/fatal` — CLI: `on|off|restart|status|config|demo|crt on|off|toggle|sync +|-`.
- `shell/shell.qml` — reparte qué dibuja cada pantalla.
- `shell/Crt.qml` + `shell/crt.frag(.qsb)` — el tubo: vidrio, fósforo, scanlines, rotura.
- `shell/Motif.qml` — seis animaciones para las pantallas sin letra.
- `cartelitos/lyrics.py` — cadena de proveedores, cache, LRC "enhanced" (tiempo por
  palabra) y `split_repeats`.
- `cartelitos/offsets.py` — corrección de sync por artista (`offsets.toml`), separada de
  `config.py` porque la escribe el propio daemon, no Ferox a mano.
- `packaging/PKGBUILD` + `.SRCINFO` — listos, build probado con makepkg.
- `docs/demo-dialogs.gif`, `docs/crt-mode.jpg` — para el README.
- `tests/` — 353 tests, stdlib puro.

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
- De la lista de Ferox para el CRT: transición de canal (estática → rojo un microsegundo → texto
  deformado → se estabiliza), efecto IOWN (letra gigante desplazándose entre pantallas), setup
  visual con un número gigante en cada monitor.

## Decisiones cerradas (Ferox las descartó, no re-proponer)

- BSOD, sonidos, easter egg `wolf.exe` (el video de Mr Wolf es UN tema puntual — no insistir).
- Temas visuales (win95 / XP / vaporwave): le gustó la idea pero **no la pidió**. Esperar a que la
  pida.
- Defaults que él usa: `karaoke = true`, `max_dialogs = 0` (sin límite), `cascade` y `np_vinyl` en
  true.
