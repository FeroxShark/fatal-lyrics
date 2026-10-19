# Vidrio del tubo (tanda 9) — antes / después

Banco offscreen `previews/shader-check` (1920×1080, tubo arcade/custom, texto oscuro sobre campo claro).

- `esquina-antes-despues.png` — recortes ×4 de las esquinas: izquierda antes (esquina viva, escalera de 1 px),
  derecha después (radio, borde suave, bisel y filo).
- `convergencia-antes-despues.png` — arcade, texto de la esquina y del centro ×4: el centro pierde el franjeado R/B.
- `negro-x8-antes.png` / `negro-x8-despues.png` — campo negro ×8 de brillo: el reflejo de arriba a la izquierda y el filo.
  Máximo sobre el negro: +7/255 en el pico del reflejo; el centro no cambia.
