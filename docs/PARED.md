# La PARED de motivos (fase 1, 2026-10-22)

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

## Los tres motivos de esta fase

- **truchet**: el shader recibe `view` (ventana en unidades de `span`), `foc` (el foco) y `wallK`;
  las ondas salen del foco (la letra) en vez de una esquina al azar.
- **mystify**: el shader pinta en px de lienzo (`win`, `orig`); los rebotes escalan con el ancho
  del lienzo (`wallKx/Ky`) para que el polígono cruce la pared a la misma velocidad aparente.
- **pipes**: la grilla 3D crece con el lienzo (5..30 celdas por eje), más caños por frase, y el
  aro sale del foco. Los caños fuera de la ventana no se dibujan.

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
5. Banco: sumarlo a `KINDS` de `previews/crt-motifs/pared.py` y correr `./pared.py --check` (y
   `--cam 1.06 --zoom 1.04`): la media por pantalla contra la referencia tiene que dar < 0,5.
6. Test: sumarlo a `WALL_KINDS` de `tests/test_pared.py`.
7. Una pantalla sola tiene que quedar igual: comparar contra el commit anterior con `render.py`.

**Ojo:** una propiedad de ShaderEffect no se puede llamar `focus` (es FINAL en Item; TRAMPAS).

## Banco (offscreen, `previews/crt-motifs/pared.py`)

Layouts: `2` (DP-2 vertical + HDMI-A-1, instrumental), `3` (el equipo de Ferox, letra en el medio),
`3i` (el mismo, instrumental), `3h` (tres 1920×1080, letra en el medio). Cada pantalla con su
instancia contra UNA instancia que dibuja el lienzo entero (`--ref`).

Resultado 2026-10-22 (media por pantalla 0..255, recorte contra la referencia): sin cámara, peor
0,02 en los 4 layouts × 3 motivos; con `--cam 1.06 --zoom 1.04`, peor 0,17. Sin errores QML. A ojo
(3-truchet, 3-pipes, 3i-mystify, 2-pipes) el dibujo sigue de una pantalla a la otra. Pantalla
sola contra `3e63bbf` (apaisada y vertical): media 0,0.

## Supuestos (fase 1) y lo que sigue

- El mundo sigue por detrás de la pantalla de la letra (no se re-encuadra el lienzo sin ella).
- Una cámara con `camS` distinta por pantalla no se corrige: la pared se ve continua cuando todas
  laten igual (el golpe ya es de pared). DP-1 participa.
- Fase 2: más motifs extensibles (dunes, ocean, pond, stars, tunnel son los candidatos naturales),
  verlo con música real en el equipo, y decidir si el sorteo debería preferir la pared.
