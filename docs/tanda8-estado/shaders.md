# Tanda 8 — slice `shaders`

Dos arreglos visuales, sólo en shaders (`.frag` + `.qsb`) y, si hace falta, el `.qml` dueño.

## Hecho
- (nada todavía)

## En curso
1. Túnel: franja a media altura a la izquierda (`bug-tunel-corte.png`).
   Hipótesis: costura de `atan` en x<0, y=0 — `ang` salta de +0.5 a -0.5, `ab = a*12` salta 12
   y `brick = floor(ab)` cambia de índice: `brickTone(brick, course)` da OTRO tono a cada lado.
2. crt.frag: moiré de scanlines/máscara (círculos en las esquinas, estrella en el centro).
   Hipótesis: scanline de período 2 px en coordenadas curvadas = justo Nyquist; la curvatura
   estira la frecuencia por encima y el batido con la grilla de píxeles dibuja las figuras.
   Máscara con bordes duros (armónicos por encima de Nyquist).

## Falta
- renders antes/después a 1920×1080 y 1080×1920 (DP-5 va rotado), análisis FFT.

## Supuestos
- Monitores (hyprctl, sólo lectura): HDMI-A-2 1920×1080, DP-4 1920×1080, DP-5 1920×1080 transform 1
  (vertical 1080×1920). Escala 1.0 en los tres.

## Cómo retomar
- Leer este archivo, `git log --oneline -- shell/tunnel.frag shell/crt.frag docs/tanda8-estado`.
