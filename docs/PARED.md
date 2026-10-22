# La PARED de motivos (fases 1 y 2, 2026-10-22)

Pedido de Ferox: en el CRT, cuando no hay letra (instrumental) o la letra ocupa una pantalla, las
demás no repiten cada una su dibujo: lo extienden entre pantallas como UN lienzo continuo. Con la
letra en el medio tiene que verse armónico. Una pantalla sola: nada cambia. Perilla para apagarlo:
`crt.wall` (default `true`, fila "Span the wall" en Ajustes).

## Cómo funciona

- **El lienzo** (`Wall.canvas`): la caja de todas las pantallas del tubo, en px lógicos del
  compositor. Los huecos entre monitores (DP-2 asoma 370 px por arriba de HDMI-A-1) y la pantalla
  de la letra son mundo que nadie ve: el dibujo sigue por detrás. `span` = el lado corto de la
  pantalla más chica, la medida de los trazos (un trazo mide lo mismo en todas).
- **Cada pantalla corre SU instancia** (un `Crt.qml` por pantalla, como siempre) y dibuja el
  recorte `Wall.view(off, size, pv, o, s, z)`: la ventana del lienzo que le toca con la cámara
  puesta. Lo que se ve queda como si TODA la pared escalara `s·z` sobre el pivote de pared
  (`tests/test_pared.py` lo prueba punto por punto). El tirón propio del motivo (`zoomNow`) va
  dentro de la ventana, no en el `Scale` del Motif (partiría la costura).
- **Lo compartido** (root, `shell.qml`, bloque PARED): tipo (`crtWallKind`), semilla
  (`crtWallSeed`, guardada en `crtWallShare.seed`), reloj (`crtWallEpoch`, `Date.now()`), estado
  mutable (`crtWallShare`: `movAt/mov/beatN/tick/tickAt/own` de MotifBase y
  `dAt/dens/drift/temper` de ThumpBase — la primera instancia que llega lo escribe, las demás lo
  leen), cara de colores (`crtWallRef`: la primera pantalla sin letra) y foco (`crtWallFx/Fy`: el
  centro de la pantalla con la letra, o el del lienzo; se mueve con `Motion.cameraMs`).
- **El reparto** (`crtWallSettle`, después de cada `crtMotifRefresh`): si una pantalla saca un
  dibujo de pared, lo toman TODAS las vivas con una semilla; la pared cambia sólo cuando vence su
  hold, por un forzado o porque deja de valer (menos de dos pantallas, perilla apagada). Al vencer
  tiene un tiro más para seguir en pared; si no sale, cada pantalla vuelve a un dibujo propio
  (sin dibujos de pared: uno solo no es pared). Una pantalla que se suma tarde (hotplug, una que
  estaba apagada) toma la semilla y el estado de la que corre.
- **El enganche** (`Crt.wallLatch`): la pantalla entra o sale de la pared sólo en el puente de
  glitch (`motifBridge`), nunca a mitad de un dibujo. `fatal crt motif <kind> --screen all` con un
  kind de pared muestra la pared.

## La pantalla de la letra (Ferox 2026-10-22)

La pantalla que tiene la letra NO lleva la pared debajo: queda limpia, como en el modo por
pantalla (sólo la letra y su fondo, `pal.bg`). Vale también con el dibujo forzado
(`fatal crt motif <kind> --screen all`): en pared el forzado ya no pinta debajo del verso. Las
otras pantallas comparten el dibujo y cada motivo declara cómo (`wallFit`, en su `.qml`; default
`"behind"` en `MotifBase`/`WallBase`/`WallItem`; la cuenta es `Wall.fit`):

- **`"behind"` (detrás)**: el mundo sigue por detrás de la pantalla de la letra como si fuera una
  ventana opaca; lo que sale por un lado reaparece por el otro con la geometría real. Es el lienzo
  de siempre: la letra no cambia ninguna ventana. Lo usan los de movimiento con dirección:
  **mystify, pipes, dunes, ocean**.
- **`"mirror"` (espejo)**: el lado CORTO (el que menos se aleja del centro de la pantalla de la
  letra) se espeja sobre ese eje y se da vuelta (`Scale` -1 en `motifFrame`): las dos alas
  muestran el mismo dibujo, enmarcando la letra. El reflejo del lado corto cae dentro del lado
  largo, así que el lienzo, el reloj y el estado compartido no cambian; el pivote de la cámara y el
  foco también se reflejan (lo que se ve es el reflejo de la pared entera escalando sobre su
  pivote). El eje es x si las demás pantallas están a los costados, y si no y (pantallas apiladas).
  Lo usan los campos que salen del foco: **truchet, pond, stars, tunnel**.
- **`wallEcho`** (0..1, default 0): un eco muy tenue y desenfocado (`MultiEffect`, blur) detrás de
  la letra. Ningún motivo lo usa: rompe "una animación por pantalla" y no quedó mejor en ninguno.

Sin letra (instrumental), con la letra en un borde, o con una pantalla sola: todas dibujan su
rectángulo del lienzo, como antes. **Transiciones:** en pared el dibujo de la pantalla que recibe
la letra se va con `Motion.exitMs` (InQuad) y vuelve con `Motion.enterMs` (OutExpo) cuando la
letra se va (`wallShow`); la pantalla espejada que cambia de lado (la letra salta, o se va) lo
hace en el PUENTE (`motifBridge`), con la letra de partida enganchada en `motifWall.text`. Si la
ventana de una pantalla no cambia, el cambio es mudo. La letra la dice el root: `crtWallText`
(-1 sin letra).

## Los motivos de la fase 1

- **truchet**: el shader recibe `view` (ventana en unidades de `span`), `foc` (el foco) y `wallK`;
  las ondas salen del foco (la letra) en vez de una esquina al azar.
- **mystify**: el shader pinta en px de lienzo (`win`, `orig`); los rebotes escalan con el ancho
  del lienzo (`wallKx/Ky`) para que el polígono cruce la pared a la misma velocidad aparente.
- **pipes**: la grilla 3D crece con el lienzo (5..30 celdas por eje), más caños por frase, y el
  aro sale del foco. Los caños fuera de la ventana no se dibujan.

## Los motivos de la fase 2 (dunes, ocean, pond)

Los tres llevan reloj propio y no heredan de `MotifBase`: heredan de `shell/WallBase.qml`, que les
da lo mismo en chico (`wall`, `wallCam`, `tubeClock`, `seed`, `wallView`/`wallCfg`, `wallFocusU`,
`wallTime(rate)`, `wallHash(n)`, `wallStamp(n, now)`). Sin `wall` no se usa nada: `wcfg.x = 0` y
el shader sigue la misma cuenta de antes (`S = res.y`, `yy = uv.y`).

- **Reloj**: con `tubeClock >= 0` el reloj de las tres instancias es UNO (`wallTime`, acumulado
  en `wall.share`); el banco (`tubeClock -1`) se lo pasa de afuera y el FrameAnimation no corre.
- **Azar**: pisotones y piedras salen de `wallHash(beat)` (semilla de la pared), no de
  `Math.random`; `wallStamp` fija el instante del golpe para todas y `slot = beat & 1`. El x del
  pisotón se reparte por el ancho del lienzo.
- **dunes / ocean**: UNA cámara en perspectiva para todo el lienzo: el horizonte es una sola raya
  (30 % / 34 % del alto del lienzo), la unidad es `span` y cada pantalla dibuja su ventana
  (`view`). DP-1 queda con su horizonte en el borde de arriba: es lo que pasa si el lienzo es UNO.
- **pond**: el agua es una sola; la retícula queda anclada al lienzo y los anillos salen del foco
  (la pantalla con la letra, o el medio): `fo` y `R = wallReach` (la esquina más lejana).
- Uniforms nuevos (`view`, `wcfg`, `fo`) al FINAL del bloque std140; `.qsb` recompilados.
- **Banco**: `sync-shell.sh` pone en 0 las duraciones de los `Behavior` y de `liftAnim` de estos
  tres en las copias (si no, cada instancia anima en tiempo real y la comparación no es
  cuadro a cuadro: una diferencia de ~1 px que crecía hacia abajo era la arena levitando).

## Los dos motivos de la fase 2 (stars, tunnel)

Los dos no heredan de `MotifBase`: son hijos de `shell/WallItem.qml` (base mínima: `wall`, `wallCam`,
`wallT`, `walled`, `wallWin`, `wallPx`, `wallFocus`, `span`, `wallNow()`), que da lo mismo que la receta
de abajo sin traer el feed de ritmo. Una pantalla sola: igual que antes (el túnel con el shader viejo
y los mismos uniforms da 0 de diferencia en apaisado y vertical; las estrellas hacen las mismas
cuentas con `k = 1`).

- **stars**: `shell/Stars.qml` (salió de `Motif.qml`). El campo es UNO y sale del foco (la letra):
  `reach` llega a la esquina más lejana del lienzo, `k = reach / (span·1,05)` es cuántas veces más
  largo es el radio que en una pantalla. La fase avanza `1/k` de rápido (una estrella recorre los
  mismos px/s que en una pantalla sola) y el número de estrellas crece con `k^1,5` (tope 900: son
  ítems por pantalla, y las que caen fuera de la ventana no se pintan). La distancia viajada vive en
  `wall.share.stars`.
- **tunnel**: `tunnel.frag` gana `win` (ventana en px de lienzo), `foc` (el punto de fuga = el foco, o
  sea el túnel se ve desde adentro con la letra en el centro) y `spn` (la medida del anillo). Sin pared
  son `(0,0,res)`, `res/2` y `min(res)`: la misma cuenta de antes. El pixel de filtro sale de la
  ventana (`pxq`), no de la textura. El estado (`travel/clock/roll`, la luz que corre) vive en
  `wall.share.tun`; la luz es UNA para toda la pared y cada pantalla la recalcula al plantarse
  (`wallLightSync`), así que el orden en que les llegan las señales no importa.
- **Supuestos**: en pared el empujón de brillo del golpe no se suma (dura un cuadro y cada copia se
  lo sumaría): si la luz ya corre, el golpe no planta otra. Un golpe y un tiempo en el mismo cuadro
  plantan la luz más fuerte.
- **Bench**: el reloj externo (`wall.now()` = `pared.t`) manda los pasos (`wallT` → `wallStep`) y apaga
  los `Behavior` y la `FrameAnimation`: el túnel y las estrellas salen deterministas.

## Hacer un motif extensible (receta)

1. El motif ya hereda de `MotifBase`/`ThumpBase`: con `wall` puesto trae `walled`, `wallArea`
   (el lienzo en px), `wallWin` (su ventana en px de lienzo), `wallPx`/`wallView` (la ventana
   para un shader, en px o en unidades de `span`), `wallFocus` y un `span`/`portrait` de pared.
   El reloj, `beatN`, `mov` y la física ya salen compartidos.
2. Dibujar en coordenadas de LIENZO: en un shader, `p = win.xy + qt_TexCoord0 * win.zw` (o
   `uv = view.xy + …`); en Shapes, restar `wallWin` y multiplicar por `width / wallWin.w`. Todo lo
   que hoy sale de `width/height` sale de `wallArea`, y todo azar sale de `seed` (es el mismo en
   todas las pantallas). Nada de estado propio que no esté en `wall.share`.
3. `Motif.qml`: en su bloque, `wall: motif.wall` y `wallCam: motif.wallCam`.
4. `shell.qml`: sumar el kind a `motifWall`.
4b. En el `.qml` del motivo, `wallFit: "behind"` (mundo con dirección: sigue por detrás de la letra)
   o `"mirror"` (campo simétrico o que sale del foco: alas espejadas). Si el dibujo tiene texto
   propio, `"behind"` (el espejo lo daría vuelta). `wallEcho` sólo si de verdad queda mejor.
5. Banco: sumarlo a `KINDS` de `previews/crt-motifs/pared.py` y correr `./pared.py --check` (y
   `--cam 1.06 --zoom 1.04`): la media por pantalla contra la referencia tiene que dar < 0,5.
6. Test: sumarlo a `WALL_KINDS` de `tests/test_pared.py`.
7. Una pantalla sola tiene que quedar igual: comparar contra el commit anterior con `render.py`.

**Ojo:** una propiedad de ShaderEffect no se puede llamar `focus` (es FINAL en Item; TRAMPAS).

## Banco (offscreen, `previews/crt-motifs/pared.py`)

Layouts: `2` (DP-2 vertical + HDMI-A-1, instrumental), `3` (el equipo de Ferox, letra en el medio),
`3i` (el mismo, instrumental), `3h` (tres 1920×1080, letra en el medio), `2t` (DP-2 + HDMI-A-1, letra
en HDMI-A-1: borde), `3e` (el equipo, letra en DP-2: borde), `3v` (tres 1920×1080 apiladas, letra en el
medio: espejo en y). El `wallFit` sale del `.qml` del motivo (`--fit` lo pisa). Una pantalla espejada
se mide contra el recorte reflejado y dado vuelta de la referencia; con cámara, contra
`--ref --ref-mirror` (la referencia escalando sobre el pivote reflejado). Cada pantalla con su
instancia contra UNA instancia que dibuja el lienzo entero (`--ref`).

Resultado 2026-10-22 (media por pantalla 0..255, recorte contra la referencia): sin cámara, peor
0,02 en los 4 layouts × 3 motivos; con `--cam 1.06 --zoom 1.04`, peor 0,17. Sin errores QML. A ojo
(3-truchet, 3-pipes, 3i-mystify, 2-pipes) el dibujo sigue de una pantalla a la otra. Pantalla
sola contra `3e63bbf` (apaisada y vertical): media 0,0.

Fase 2 (dunes, ocean, pond): sin cámara, peor 0,01 en los 4 layouts; con `--cam 1.06 --zoom 1.04`,
peor 0,17. Pantalla sola: el camino sin pared del shader es idéntico por construcción (el diff del
shader sólo agrega ramas con `wcfg.x`); `render.py` no sirve para compararlo a píxel porque los
pisotones y piedras de una pantalla sola salen de `Math.random` y el reloj de tiempo real.

Resultado fase 2 (2026-10-22): stars 0,00 en los 4 layouts, con y sin `--cam 1.06 --zoom 1.04`. Tunnel
0,00 casi siempre; queda una mancha de brillo en el instante t=2 s de algunos layouts (hasta ~3 de
media, p99,5 ≤ 23), que es la luz recién plantada: el banco entrega las señales de golpe y tiempo
a cada instancia en orden distinto, y la luz toma `low` de ese instante. En el equipo real es un
cuadro de 900 ms: no se ve. A ojo (3-stars, 2-stars, 3-tunnel) el campo sale de la pantalla de la
letra y sigue de una pantalla a la otra.

Pantalla de la letra limpia + detrás/espejo (2026-10-22, 7 layouts × 8 motivos): sin cámara, peor
0,01 fuera del túnel en t=2; con `--cam 1.06 --zoom 1.04`, peor 0,31 (3v pipes). Las espejadas dan
lo mismo que las otras (3-truchet, 3h-stars, 3v-pond con la ala dada vuelta: ≤ 0,02). El túnel en
t=2 s sigue con la mancha de la luz recién plantada, y es **no determinista**: el commit anterior
(`5e2cbc9`, sin estos cambios) da entre 0,3 y 16 de media corriendo tres veces lo mismo (3h). En
t=6,5 s: ≤ 0,2 en todos (2-tunnel con cámara 0,75). A ojo (3-truchet, 3-tunnel, 3-mystify, 3v-pond,
2t-dunes, 3e-ocean, 3h-stars, 3-pipes): la letra limpia, las alas del espejo simétricas sobre ella y
el "detrás" sigue de una pantalla a la otra saltando la de la letra.

## Supuestos (fase 1) y lo que sigue

- El mundo sigue por detrás de la pantalla de la letra (no se re-encuadra el lienzo sin ella), o se
  espeja (`wallFit`); la pantalla de la letra nunca lo muestra.
- Una cámara con `camS` distinta por pantalla no se corrige: la pared se ve continua cuando todas
  laten igual (el golpe ya es de pared). DP-1 participa.
- Siguiente: verlo con música real en el equipo (con todos los motifs de la fase 2) y decidir si el sorteo debería preferir la pared.
