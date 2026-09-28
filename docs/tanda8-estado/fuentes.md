# Tanda 8 — slice `fuentes`

Sacar la fuente pixel de bloques que a Ferox no le gusta y sumar 3-4 fuentes libres nuevas,
repartidas por set. Sólo `shell/fonts/` y el cableado de la fuente del set (`shell.qml`,
una línea de `Crt.qml`). Nada de shaders ni audio.

## Hecho
- (nada todavía)

## En curso
- Confirmado: la de la captura (`font-pixel-no-gusta.png`, "WHEN I'M AWAY") es **Press Start 2P**
  (W con patas escalonadas, A con la muesca: render PIL lado a lado idéntico, más gruesa por el
  bold sintético de `font.bold: true`).
- Candidatas bajadas de `github.com/google/fonts` (raw, rama main), todas OFL 1.1, todas cubren
  áéíóúñÁÉÍÓÚÑüÜ¿¡ (chequeado con fontTools sobre el cmap).

## Falta
- Sacar `press` del pool, borrar ttf + LICENSE, repuntar los previews que la cargaban.
- Sumar las nuevas, pool por familia de entrada, test, hoja de muestra.

## Supuestos
- (se completan abajo)

## Cómo retomar
- `git log --oneline -- shell/fonts docs/tanda8-estado/fuentes.md`
