# Showreel de animaciones — preview (no integrado)

Reel de 15 s (128 BPM, 8 compases, 1080p60) con animaciones nuevas y reactivas para los
carteles. **Nada de esto toca el overlay**: es QtQuick puro, renderizado offscreen.

```bash
./render.py                          # out/showreel.mp4 (con pista sintética)
./render.py --segments               # + un mp4 por módulo + GIF + contact sheet
./render.py --stills 5.5,11.3        # PNGs sueltos en out/stills
./render.py --from 11 --to 13.6 -o out/drop.mp4
./sheet.sh out/hoja.png 3 out/stills/*.png   # hoja para mirar varios cuadros juntos
```

`render.py` FUERZA `QT_QPA_PLATFORM=offscreen` (la sesión exporta `wayland` y con `setdefault`
la ventana se abría en pantalla). Shader: `qsb --glsl "100 es,120,150" -o post.frag.qsb post.frag`.

## Cómo está hecho

- Todo es función pura de `t` (Reel.qml): ni un Timer ni una Animation → render determinista y scrubeable.
- `Timeline.js` es el guion (partitura, cortes, letra). `SyntheticAudio.qml` publica los MISMOS
  nombres que `root` en `shell/shell.qml` (`audLevel`, `audLo/Mid/Hi`, `audBeat`, `audPeak`,
  `bpm`, `lastBeatAt`, `wave`): al integrar, un módulo se bindea con `audio: root`.
- `Win95Dialog.qml`: el cartel con geometría explícita (`buttonRect(i)`, `bodyRect`).
- `post.frag`: vidrio del reel (tubo on/off, glitch-puente, RGB split, flash/negativo, scanlines).

## Módulos (`modules/`) y qué haría falta para integrarlos

| # | Módulo | Qué hace | Integración |
|---|---|---|---|
| 01 | Boot | prompt DOS + cartel que nace pixel → raya → resorte | spawn alternativo: reemplaza scale/opacity de `spawnAnim` |
| 02 | Stack | foco activo/inactivo, cámara que sigue, estela de arrastre Win95 | inactivo por edad = fácil; estela = copias congeladas en `dragBy` |
| 03 | Kinetic | letra por letra con `words`, "fatal" se escapa y deja burn-in | entrada por letra = variante del karaoke; escape = candidato `word_fx` |
| 04 | Mitosis | un cartel se divide a tempo hasta 128, ola de "(No responde)" | modo drop con compás confiable; necesita presupuesto en `pace` |
| 05 | Drop zoom | zoom infinito a través de "Aceptar", scope con `wave` | entrada de `cue drop`; el scope ya lee el `wave` real |
| 06 | Resolve | lockup que se descifra, click, apagado del tubo | descifrado para la funda / `crt.intro_card` |

Regla de la casa respetada: entradas con el snap OutExpo de `Motion.qml`, glitch sólo como
puente de pocos cuadros entre escenas, holds largos. El audio del MP4 es sólo para ver la
sincronía (el overlay sigue sin sonidos: decisión cerrada).
