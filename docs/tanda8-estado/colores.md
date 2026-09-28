# Tanda 8 / slice "colores" — estado

Alcance: el fondo del CRT deja de ser SIEMPRE 2-1 con 3 monitores. Paletas de TRES caras
(las 6 fijas + la de la tapa), reparto que sigue la parte del tema, perilla para volver a lo
de antes. Cero corridas en pantalla: sólo tests y renders offscreen.

## Pedido (Ferox, aprobado)
1. Paletas de 3 colores que armonicen (no un tercero random). La de la tapa saca 3 colores de
   la carátula con contraste entre sí y contra el texto. Respetar cara clara/oscura; el texto
   se lee en los 3 fondos.
2. Reparto por sección: estrofa = 2-1 (como ahora); estribillo = las 3 iguales (el golpe);
   puente / momentos raros / eventos raros = las 3 distintas. Con <3 monitores, degradar con
   criterio. Cambios con transición, sin chocar con la infección ni con `crt_color_hold`.
3. Perilla `crt.face_mode = song | classic`, default `song`.

## Plan
- `shell/Faces.js` (`.pragma library`, puro, testeable con node como `React.js`): contraste
  WCAG, caras desde un color, la paleta de 3 de la tapa, `faceMode(...)` (qué parte es) y
  `facePattern(...)` (qué cara va en cada pantalla, con degradado por n).
- `shell.qml`: `c` en las 6 paletas, `albumScheme` con 3 caras, `crtFace` lee `c`, estado
  `crtFaceModeNow`, cambio escalonado pantalla por pantalla (el fondo ya anima 900 ms).
- config/ipc/setup: `face_mode`.
- Banco `previews/colores/render.py` → `docs/tanda8-estado/colores-*.png`.

## Hecho
- `895650e` `shell/Faces.js`: contraste WCAG, `faceLit`/`faceDark`/`faceMid` (la luz se corre
  lo justo para que la letra llegue a 4.5 en cualquier tono), `albumFaces` (3 de la tapa;
  tono repetido no cuenta, falta → medio del arco más grande), `checkScheme`, `faceMode`,
  `gateOk`, `twoTone` (el 2-1 de siempre), `facePattern` (degradado por n), `stepOrder`.
- `48d75af` `shell.qml`: cara `c` en las 6 paletas (tono elegido a mano, comentario por
  qué arma), `albumScheme` vía `Faces.albumFaces` + `qtFace`, `crtFace` indexa [a,b,c],
  `crtFaceMode`, `crtFaceModeWant/Now`, `crtDropSeen`, `faceSteps` (una pantalla cada
  `Motion.enterMs`, desde la de la letra), `crtFaceTick` en el Timer de la infección ANTES
  de ella, la infección espera si hay pasos, `resetFacesOnPeak` re-reparte dentro de la parte.
- `0485e6f` `83e5979` `df07a43` perilla `crt.face_mode` en config/ipc/setup.
- `d0d0b83` `8a16d55` tests: el viejo de las 5 claves ahora pide 6×3 + Faces.js;
  `tests/test_colores.py` (20).

## Falta
Banco `previews/colores/` + PNGs, TRAMPAS/PENDIENTES/CLAUDE.md.

## Supuestos
- "Paleta/cara invertida" (así la llaman TRAMPAS y `tunnel.frag`) = la cara CLARA `a` (fondo
  claro, letra oscura: el CRT al revés). La oscura es `b`. La tercera (`c`) es una cara MEDIA:
  fondo saturado de luminancia intermedia (Y≈0.11), letra casi blanca del mismo tono — separa
  por LUZ, no sólo por tono, y el texto pasa 4.5 de contraste en las tres.
- Secciones: sólo la del daemon (`quiet|verse|build|drop`, ya sin rebotes). estribillo =
  `drop`; puente = `build`, o `quiet` DESPUÉS del primer drop del tema (antes es intro/estrofa
  floja); raro = `crtRare` corriendo. NO se usa `rep.chorus` por línea: flapea línea a línea.
- Degradado: n=1 verse [a], drop su cara, puente [c]; n=2 verse 1-1 de a/b, drop iguales,
  puente foco + media. El foco (pantalla con la letra) conserva su cara en todos los cambios.
- Portero: entrar a drop/puente/raro pasa ya (el golpe no espera 10 s y un raro dura 3-6 s);
  volver a verse espera `color_hold`; piso 2,5 s entre dos cambios.

## Cómo retomar
Leer este archivo y `git log --oneline -- docs/tanda8-estado/colores.md shell/Faces.js`.
