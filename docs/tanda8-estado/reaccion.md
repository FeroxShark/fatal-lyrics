# Tanda 8 / slice "reaccion" — estado

Alcance: respuesta VISUAL a las señales nuevas de `aud` (`cut`/`cutf`/`hf`, ver `senales.md`) y
movimiento propio del grano de la estática (`dirt`). No se toca `cartelitos/audio.py`, `shell/fonts/`
ni el tablero de la intro / "SIGUE:". Cero corridas en pantalla: sólo tests y renders offscreen.

## Pedido
1. Silencio seco (`cut`): bajar la luz de los tubos durante el corte y volver con el golpe (`cutf`).
   Inmediato y corto; distinto del `quiet` de sección.
2. Agudos/melodía (`hf`): respuesta PROPIA, distinguible del golpe del bajo, sin romper "una
   animación por pantalla".
3. Estática por suciedad: que el grano se mueva (deriva, ondulación, bandas) y responda más rápido.

## Hecho
(nada todavía)

## En curso
- Diseño + banco offscreen.

## Supuestos
(se completan al decidir)

## Cómo retomar
- `git log --oneline -- docs/tanda8-estado/reaccion.md shell/crt.frag shell/Crt.qml shell/shell.qml`
