# Tanda 8 / slice "mystify" — estado

Pedido de Ferox: "creo que es la que más consume, podría ser mucho mejor y comer menos recursos".
Cero corridas en pantalla: sólo banco offscreen (`previews/crt-motifs/`). No se tocó Maze, Speed.js ni audio.py.

## 1. Medición (`previews/crt-motifs/bench.py`)
Mystify **no** era el más caro: ver tabla en `docs/NUMEROS-MEDIDOS.md`. En el banco swarm (≈15 ms), defrag
(≈8) y pipes (≈7) lo pasan por mucho; mystify quedaba con splitflap/harmonograph (≈3). El costo no era un
Canvas en CPU (eso se sacó el 2026-09-27) sino las 15 tandas de Shape con 3×22 polilíneas de trazo ancho que
JS armaba y Qt tessellaba en CPU en cada cuadro (0.75 ms sólo del lado QML).

## 2. Reescritura barata
`shell/mystify.frag` (+ `.qsb`): UN ShaderEffect de pantalla completa. Cada eco de la estela es el polígono
evaluado `e·gap` segundos atrás en el mismo reloj periódico (ondas triangulares, rebotes enteros por loop),
y el píxel se queda con el eco más cercano (distancia a segmento, analítico). No hay feedback recursivo a
propósito: `ShaderEffectSource` recursivo depende de la historia y el banco exige que cada cuadro sea función
pura del reloj (costura 0 medida: `./render.py mystify` → "costura: media 0.000 máx 0"). La CPU manda ~20
números por cuadro; los vértices (`bounces`/`start`, sembrados con `seed`) viajan una vez en 6 `mat4`.
`Mystify.qml` conserva el nombre `bounces()` (no `rate()`: pisaba la propiedad heredada, TRAMPAS) y la fase
integrada `lt = clock + movOff`. Número de ecos ≤ 24 con `quality`.

## 3. Mejor visualmente
- Línea nítida (borde antialias de 1 px analítico) + resplandor exponencial; la estela se desvanece en
  degradé continuo (brillo `(1-a)^1.7`, grosor 100→45 %), no en 3 escalones.
- Color dentro de la paleta de la cara: `ink`→`hot`, con una deriva periódica (2 vueltas en el loop) que
  también recorre la estela; el polígono de adelante se enciende en `hot` con el tiempo.
- Reacciona: `lt` (que ya trae el ritmo integrado) mueve los vértices; `surge` abre y estira la estela;
  `energy` da la cantidad de ecos; `high` corre el color hacia `hot` y ensancha el resplandor; el golpe del
  tiempo engrosa el núcleo; el drop trae el tercer polígono desde el centro.
- Borde: margen 7 % (antes 6 %) para que el rebote no se coma la curvatura del tubo `arcade`.

Hoja: `mystify-hoja.png` (cuadros 2, 7, 10 y 13.5 s con el vidrio, `arcade`/`bloodline`).

## Pendiente / no hecho
- `cut`/`cutf`/`hf` **no llegan a los motivos** (`Motif.qml` no los expone, sólo el tubo). Se usó `high`
  como agudos y `surge` para la estela; "estela más larga en los cortes" y "color con hf" reales piden
  pasar `audCut`/`audHf` por `Motif.qml` (archivo que toca otro worker).
- No se verificó en el overlay vivo (prohibido): recordar reiniciar Fatal Lyrics al integrar, un `.qsb` no
  se recarga en caliente.
