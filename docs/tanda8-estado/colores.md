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
(nada todavía)

## Falta
Todo lo del plan.

## Supuestos
- "Cara invertida" = la cara oscura (`b`: fondo hondo, letra encendida) frente a la clara
  (`a`). La tercera (`c`) es una cara MEDIA: fondo saturado de luminancia intermedia, letra
  oscura o clara según cuál tenga más contraste. Así las 3 se separan por luz, no sólo por tono.
- Secciones: el daemon manda `quiet|verse|build|drop` (energía) y cada línea trae `rep.chorus`
  (letra). estribillo = línea `chorus` o sección `drop`; puente = `build`, o `quiet` DESPUÉS de
  haber pasado un estribillo en el tema; raro = `crtRare` corriendo.

## Cómo retomar
Leer este archivo y `git log --oneline -- docs/tanda8-estado/colores.md shell/Faces.js`.
