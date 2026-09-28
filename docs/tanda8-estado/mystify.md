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

## 4. `cut` y `hf` reales (slice mystify-señales)
Ahora llegan por el mismo camino del laberinto: `Crt.qml` → `Motif.qml` (`cut: motif.cut`, `hf: motif.hf` en
`mystifyC`) → `MotifBase`. Nada nuevo en `Speed.js` ni `audio.py`.
- **Corte seco (`cut`)**: el dibujo se AGARRA. Los vértices se quedan quietos (hasta 0,6 s de fase; un
  "corte" que en realidad es una pausa no deja al polígono medio minuto atrás) y la estela se estira (`gap`
  +130 %). Al volver la música los vértices dan el salto atrasado con el snap de Motion (320 ms) y la estela
  se recoge. Sin `Behavior`: estampas de reloj (`cutAt`/`backAt` en `clock`, `freezeAt`/`thawAt` en la fase
  monótona `clock + movOff`, así el corte que cruza el 15 del loop no se va por el camino largo) y las dos
  cuentas puras de `shell/Mystify.js` (`hold`, `lag`), que llegan a 0 EXACTO — una cola exponencial no
  cerraría la costura. Un corte que ya está en curso cuando aparece el motivo cuenta desde ahí.
- **Agudos (`hf`)**: pasa por `React.fizz` (la misma curva que el tubo, umbral 0.12) y reemplaza a `high`
  en el color (`toHot`) y suma al brillo del resplandor (+80 %). `high` (nivel) queda sólo en el ancho.
- Hojas: `mystify-corte.png` (10.8 / 11.05 / 11.2 / 11.45 s: antes, agarrado con la estela abierta, el salto
  al volver, el drop) y `mystify-agudos.png` (1.99 s en calma, 2.109 hi-hat, 2.34 caja, 2.45 s).
- Costura del banco: `./render.py mystify` → "costura: media 0.000 máx 0". La primera versión daba media
  16.8: el estado inicial (`backAt`/`thawAt` en 1e9) dejaba al dibujo agarrado hasta el primer corte; sin
  corte todavía valen -1e6 (test `test_no_cut_yet_means_not_held`).
- Banco: `previews/crt-motifs/sync-shell.sh` ahora copia también `Mystify`, `mystify.frag(.qsb)`,
  `Mystify.js` y `React.js`. Tests: `tests/test_mystify.py`.
- Números a ojo (Ferox los puede tocar): agarre 0,12 s, suelta 0,32 s, atraso máx 0,6 s, estela +130 %,
  `hf` → color 0,4 y brillo 0,8.

## Pendiente / no hecho
- No se verificó en el overlay vivo (prohibido): recordar reiniciar Fatal Lyrics al integrar, un `.qsb` no
  se recarga en caliente.
- El `cut` del banco es sintético (`LoopFeed.qml`, 0,28 s); los reales miden 150–400 ms.
