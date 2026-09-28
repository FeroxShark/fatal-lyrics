# Tanda 8 — slice `shaders`

Dos arreglos visuales, sólo en shaders (`.frag` + `.qsb`). Ningún `.qml` de `shell/` tocado.

## Hecho
- `afb9cfa` **túnel sin costura** (`shell/tunnel.frag` + `.qsb`). Causa: `ang = atan(y,x)/2π` salta de
  +0.5 a −0.5 vueltas sobre el eje x negativo (izquierda, media altura). `ab = a·12` salta 12 justo
  ahí: `fract(ab)` no se entera, pero `brick = floor(ab)` sí, y `brickTone(brick, course)` le daba
  OTRO tono al ladrillo de cada lado del corte. Fix: `brick = mod(floor(ab), 12.0)`. El 12 tiene que
  ser entero e igual al de `a * 12.0`. Medido (túnel derecho, `bend` 0, 7 valores de `roll`):
  salto en la fila del corte / salto típico entre filas = 22.8 → 0.13 (1920×1080), 5.6 → 0.19 (vertical).
- `7a035c4` + `7a9c155` **vidrio sin moiré** (`shell/crt.frag` + `.qsb`).
  Causas, dos:
  1. **Scanlines** = `cos(fc.y·π + t·1.6)` con `fc` en coordenadas del tubo CURVO: período 2 px = Nyquist
     exacto. La curvatura estira la frecuencia (≈ `y·(1+k·x²)`) y el batido con la grilla de píxeles
     dibuja la estrella del centro y los círculos de las esquinas (con `mono`=1, sin máscara, la figura
     sigue: era el peine). Además el `+t·1.6` no hacía caminar un peine de 2 px: le hacía LATIR el
     contraste a toda la pantalla cada ~2 s, y con él aparecían y se iban las figuras.
     Fix: el peine va en filas de la PANTALLA (`qt_TexCoord0.y·res.y`), quieto, cresta en el centro del
     píxel, contraste 0.30 (el promedio del latido de antes; era 0.50 pico). `interlacePhase` también va
     por filas de pantalla (mismo peine de 1 fila).
  2. **Máscara** con bordes duros (tríadas en escalón, puente de 1 px de la slot, puntos recortados): sus
     armónicos pasan Nyquist y a través de la curvatura aliasean (trinitron pitch 2.4, arcade, pvm).
     Fix: cada máscara es su fundamental en cosenos (slot: producto por `cos(π(cy−0.422))` en vez del
     corrimiento en escalón, puente con 2 armónicos; puntos: red triangular = 3 cosenos a 120°), con el
     MISMO promedio por canal, y cada coseno se funde con `keepAt(f)` = 1 − smoothstep(0.36, 0.48, f),
     f = frecuencia en ciclos por píxel de PANTALLA (derivadas de `curve(uv)·res`, tomadas antes del
     glitch y del return temprano). Rejilla pitch 3 en tubo plano: 1.16/0.86/0.86 exacto, como antes.
- Banco de medición: `previews/shader-check/` (`render.py --dir <carpeta de .qsb> --tag <nombre>`,
  `moire_map.py`). Offscreen asignado, nunca abre ventana.

## Números (campo parejo por el vidrio, sin ruido/viñeta; antes → después; 1920×1080, vertical parecido)
| tubo | envolvente (contraste de la textura que varía a gran escala = las figuras) | moiré (brillo 8–200 px) | textura fina que queda |
|---|---|---|---|
| custom | 27.1 % → 0.15 % | 0.067 → 0.063 | 12.7 → 10.1 |
| trinitron | 11.4 → 0.12 | 0.34 → 0.028 | 10.6 → 7.6 |
| pvm | 21.1 → 1.0 | 0.77 → 0.25 | 18.5 → 14.2 |
| arcade | 25.3 → 0.20 | 1.38 → 1.14 (*) | 22.0 → 16.8 |
| green/amber | 32.4 → 0.6 | 0.05 → 0.06 | 13.3 → 10.6 |
(*) arcade: lo que queda es el puente de la slot mask, período 8 px, que ES su textura, no un batido.
Brillo medio por canal: igual (±0.5 de 255). Tests: 691 OK.

Renders: `docs/tanda8-estado/shaders-{moire-mapas,vidrio-esquina,tunel-costura}.png` (comprimidos);
full-res en `previews/shader-check/out/{antes,despues}/` (gitignoreado; el antes se rinde con
`--dir` apuntando a una copia de los `.qsb` de `d56d9c5`).

## Aprendido (para el cierre: TRAMPAS / NUMEROS-MEDIDOS)
- Un patrón de período 2 px en coordenadas curvas es moiré garantizado; una fase `+t` en un peine
  de 2 px no lo mueve, le hace latir el contraste.
- `cos(π·y)` en el centro del píxel (`y = n + 0.5`) da CERO: hay que restar el medio píxel.
- Medir moiré sobre 8 bits: la caja con borde "edge" rompe el peine y marca moiré falso en el
  borde; la caja simple deja pasar período 3. Usar 3 cajas + espejo, y medir también la ENVOLVENTE
  (el moiré de un peine casi en Nyquist es de contraste, no de brillo).

## Falta
- Mirada de Ferox en pantalla con música real (no se corrió nada en su pantalla).

## Supuestos
- Monitores (hyprctl, sólo lectura): HDMI-A-2 y DP-4 1920×1080, DP-5 1920×1080 rotado (1080×1920). Escala 1.
- Scanlines quietas y en filas de pantalla (no siguen la curva): reversible; alternativa = período ≥3 px
  en coordenadas del tubo + `keepAt`, que cambia la densidad que Ferox ve.

## Cómo retomar
- `git log --oneline -- shell/tunnel.frag shell/crt.frag previews/shader-check docs/tanda8-estado`.
- Rebuild: `cd shell && /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" -o X.frag.qsb X.frag`.
