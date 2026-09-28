# Tanda 8 — slice `fuentes`

Sacar la fuente pixel de bloques que a Ferox no le gusta y sumar fuentes libres nuevas, repartidas
por set. Sólo `shell/fonts/`, el cableado de la fuente del set (`shell.qml`), una línea de `Crt.qml`,
dos previews que cargaban el archivo, README (créditos) y un test nuevo. Nada de shaders ni audio.

## Hecho
- Confirmado: la de la captura (`font-pixel-no-gusta.png`, "WHEN I'M AWAY") es **Press Start 2P**
  (W con patas escalonadas, A con muesca: render PIL lado a lado idéntico; en pantalla más gruesa
  por el bold sintético de `font.bold: true`).
- `3b90694` `0f3e7ab` `390d39c` `082ef1a` — cuatro fuentes nuevas, OFL 1.1, bajadas de
  `raw.githubusercontent.com/google/fonts/main/ofl/<familia>/`, cada una con `LICENSE-<nombre>.txt`
  (el `OFL.txt` de google/fonts): **IBM Plex Mono Bold**, **Space Mono Bold**, **Chakra Petch Bold**,
  **Syne Mono** (Regular, es la única que tiene). Todas cubren áéíóúñÁÉÍÓÚÑüÜ¿¡ (cmap, fontTools).
  Plex/Space/Chakra van en el archivo Bold real porque la letra usa `font.bold: true` (con la
  Regular Qt engorda en sintético); verificado en el render: `fontInfo` da "… Bold".
- `04345d6` — `shell.qml`: fuera `fontPress`/`press`/`crtFontKeys` y la regla ">3 palabras → share"
  (era sólo para Press Start). Nueva tabla `crtFontPools` por familia de entradas del set; `crtSetFor`
  saca la fuente del mazo de SU familia con el mismo dado `crtHash(seed*7+3)`. `crtFontKeyFor` conserva
  la firma `(text, wordCount)` porque `Crt.qml` la llama así (`wordCount` quedó sin uso).
- `322fb36` — `Crt.qml`: `lyricLetterSpacing` fijo en 3 (la excepción 1 era de Press Start).
- `97a599c` — `git rm` de `PressStart2P-Regular.ttf` + su LICENSE; `previews/showreel/Reel.qml` y
  `previews/crt-motifs/Stage.qml` la cargaban por ruta → ahora VT323.
- `59d631a` — `tests/test_fonts.py` (archivo nuevo para no chocar con `test_cartelitos.py`): cada
  `FontLoader` apunta a un archivo que existe, cada ttf con LICENSE OFL y ninguna LICENSE huérfana,
  un mazo por familia de `crtEntryFamilies`, toda fuente cargada (salvo `dot`) en algún mazo, `dot`
  en ninguno, `PressStart2P` en ningún .qml/.py/.js de `shell/` ni `previews/`. Suite: 709 OK.
- `9aaa61d` — README, sección Fonts: créditos nuevos, fuera Press Start 2P.
- `f5e022d` + `dc4893d` — `previews/showreel/FontSheet.qml` + `fontsheet.py` (offscreen asignado,
  nunca abre ventana) → `docs/tanda8-estado/fuentes-muestra.png`: cada fuente como la dibuja
  `Crt.qml` (MAYÚSCULAS, bold, letterSpacing 3), rotulada con su mazo.

## Reparto (`crtFontPools`, para vetar mirando la hoja)
| familia de entradas (energy del mood) | mazo |
|---|---|
| `typed` (baja/media) | vt323, **plex**, share |
| `hard` (alta/media) | **chakra**, **space**, system |
| `burn` (alta/media) | **space**, vt323, **chakra** |
| `soft` (baja/media) | **syne**, share, **plex**, system |

## Falta
- La mirada de Ferox con música real (no se corrió nada en pantalla).

## Supuestos / cosas para mirar
- Space Mono Bold y Chakra Petch son anchas; antes Press Start tenía la regla ">3 palabras → share".
  Ahora no hay regla: confío en el `Text.Fit` de `Crt.qml`. Si una línea larga queda chica, volver a
  poner una regla por clave en `crtFontKeyFor` (ahí sigue el `wordCount`).
- `system` ("") en el render offscreen resolvió a Adwaita Mono Bold, y se parece mucho a Share Tech
  Mono con bold sintético. En la sesión real "" es el default de Qt de Ferox: puede ser otra.
- Descartadas: Courier Prime (muy máquina de escribir), Share Tech no-mono (gemela de la Mono),
  Major Mono Display (mayúsculas raras, la letra se pasa a mayúsculas), W95FA (no está en
  google/fonts: bajarla sería de un sitio de descargas), cualquier pixel de bloques (Silkscreen,
  Sixtyfour, Pixelify).
- Previews: VT323 donde estaba Press Start (el shell real usa "monospace" en `MotifBase.pixelFamily`,
  el banco ya divergía de antes).

## Cómo retomar
- `git log --oneline -- shell/fonts docs/tanda8-estado/fuentes.md`
- Regenerar la hoja: `python3 previews/showreel/fontsheet.py [salida.png]`.
- Cambiar el reparto: sólo la tabla `crtFontPools` en `shell/shell.qml`; `tests/test_fonts.py` avisa
  si una fuente queda sin mazo o un mazo nombra una clave que no existe.
