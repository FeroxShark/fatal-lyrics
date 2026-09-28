# Laberinto (`maze`) — tanda 8: marcha con la música y huevos de pascua

Estado por bloque. Hojas de contacto: `laberinto-marcha.png` (2×2: ritmo 0.6, ritmo 1.6, el corte
seco a los 10.6/10.95/11.15/11.6 s y el mundo dado vuelta) y `laberinto-eggs.png` (una fila por
huevo: carita, diálogo de error, SALIDA, rata, poliedro). Todo salió del banco offscreen
(`previews/crt-motifs`, `./render.py maze --egg <tipo> --rate <r>`, `./sheet.sh`). Ninguna corrida
en pantalla real: Fatal Lyrics no se tocó.

| Bloque | Estado | Cómo se verificó |
|---|---|---|
| Marcha por CONTADOR (`walked`, crédito `rate` por tiempo, `Maze.js: credit`) | hecho | tests node: a ritmo 1 son `d` pasos exactos; con 0.6/1.6 el crédito se conserva. Ver `laberinto-marcha.png` |
| Corte seco: se planta, mira de costado (±24°), al volver da el paso atrasado (máx. 3) | hecho | banco con el `cut` sintético de `LoopFeed.qml` (23.2–23.8 tiempos) |
| Agudos (`hf` > 0.55): vistazo de ±17° y vuelve en 0.55 s, sólo en los dos primeros pasos de cada cuatro | hecho, sin ver en pantalla | lógica por slot de pasos dentro de la vuelta, sin memoria (determinista); el `hf` del banco es sintético |
| Giro en los kicks | NO hecho | se gira sólo en los tiempos, como siempre |
| Huevos: carita, diálogo de error de Win95, SALIDA + puerta, rata, poliedro | hecho | una fila por cada uno en `laberinto-eggs.png`, todo dibujado en `maze.frag` |
| Mundo que da vuelta (`roll`): con el poliedro (16 pasos) y en el drop (40 %) | hecho | fila `flip`, `--egg flip` |
| Perilla `crt.maze_eggs` (default `true`) | hecho | `tests/test_laberinto.py` (cinco lugares) |
| Sorteo sembrado y raro: 22 % por vuelta de 32 pasos, semilla de `crtMotifSeeds` | hecho | test node de frecuencia (15–30 % en 2000 vueltas) |
| Costura del loop del banco | hecho: `costura: media 0.000 máx 0` sin huevos | con huevos sólo cierra FORZADO (`--egg`): sin forzar, el plan depende de la vuelta |

Números que se eligieron a ojo (Ferox los puede tocar): `CHANCE = 0.22`, drop 40 %, el poliedro es
un octaedro de alambre, la rata tarda 1.1 s en cruzar, el vistazo tarda 0.55 s.
