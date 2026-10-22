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

## Segunda vuelta (2026-10-22): ocho fuentes más y sorteo por mood
- Nuevas (todas OFL 1.1, `shell/fonts/` + `LICENSE-*.txt`; cubren áéíóúñüÁÉÍÓÚÑÜ¿¡): **Departure Mono**
  (pixel terminal fino, de github.com/rektdeckard/departure-mono, v1.500, .otf), **Anonymous Pro Bold**,
  **B612 Mono Bold**, **Sarpanch Bold**, **Wallpoet** (stencil), **Nova Mono**, **Xanh Mono**,
  **Rubik Glitch** (display con glitch propio; raro). El resto de google/fonts.
- Descartadas tras verlas en el vidrio: Jacquard 12 (blackletter pixel: en mayúsculas no se lee),
  Micro 5 (bloques), Michroma (muy ancha, `Fit` la achica), Lekton (x-height chica), Cutive Mono
  (máquina de escribir, como Courier Prime), Fragment Mono/Cousine (gemelas de Plex/Anonymous), Bungee.
  Sin licencia libre clara o sin ttf estable: VCR OSD Mono, Glass TTY VT220, W95FA, Fixedsys Excelsior.
- Criterio: el mazo sigue saliendo de la familia de entradas del set (tipeada→terminal, dura→filo…) y
  ahora `crtFontPick` pondera por mood: `crtFontTraits` da a cada fuente energía `e`, valencia `v` y
  peso `w`; peso = `w` × campana(mood − e/v), piso 0,08. Mismo dado `seed*7+3`, sigue siendo puro.
  Distribución medida (mazo `burn`, 1000 dados): tema lento/triste 40 % vt323 · 21 % departure ·
  2 % glitch; agitado/oscuro 22 % sarpanch · 21 % chakra · 15 % wallpoet · 8 % glitch.
- Nitidez: el banco pasa la letra por el tubo real (texturas ×2, `signal.frag`, `crt.frag`) en 4 tubos;
  Departure Mono (celda de 1/11 em) se lee limpia aun a ~34 px con `Text.Fit` sin ajustar el cuerpo a la
  grilla del pixel; las Regular-only siguen sin `bold` sintético (`crtFontBold`).
- Banco: `previews/fuentes-crt/render.py [--tube pvm] [--only a,b] [--extra ruta.ttf[:bold]]`
  → `docs/tanda8-estado/fuentes-crt/{trinitron-p1..3,arcade-p1}.png`.
- Los cartelitos del modo normal siguen con la fuente del sistema a propósito (el chrome Win95 no tiene
  equivalente libre; W95FA/Fixedsys no son OFL): `crt.font` sólo toca el CRT.
