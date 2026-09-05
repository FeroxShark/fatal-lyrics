# cartelitos — Números medidos

Mediciones de CPU/latencia y cómo se tomaron. Los números nuevos van acá.
Movido tal cual desde `CLAUDE.md` el 2026-09-05.

- **El presupuesto de eventos, medido con `docs/plans/pace-count.py`** (tema falso de 90 s, un
  verso cada 3 s, tres pantallas, secciones cada 13 s, un pico cada 12 s). Antes de la corrida 3
  de la tanda 4: **89** cambios de dibujo (30 por pantalla: uno por verso), **55** roturas,
  **2** cambios de canal, con el color de la pared dándose vuelta en cada pico. Después, en
  `normal`: **14 cambios de dibujo en 60 s** (uno cada 12.8 s por pantalla) y el resto contra los
  porteros de la tabla. `wild` devuelve los números de antes.
- La corrida 2 de la tanda 3 NO subió el costo: con un aparejo fijo (motivos forzados por la
  letra, un verso cada 2 s, ocho muestras de 8 s) el overlay pasó de **41 %** de un core a
  **35 %**. Baja sobre todo porque la grilla de ojos eran quince Canvas y ahora son cuatro; lo
  que se agregó (las hebras del aro, el rayo del salto) dura menos de medio segundo por verso.
- CRT prendido, baseline de la corrida 4 de la tanda 4 (`docs/plans/cpu-bench.py`, dos corridas
  de ocho muestras de 8 s, tres monitores, Spotify PARADO): **31-53% de un core**, media
  **41%** (39.1 y 42.9 las dos corridas). El aparejo fuerza los motivos caros por la letra
  (tunnel / rorschach / ekg) y manda un verso cada 2 s, así que es el techo, no el uso normal.
  Es el número contra el que se compara de acá en adelante: el "20-37%, media 29" viejo se
  midió con otro aparejo y no es comparable. Apagado: 1.7% (sin captura, sin texturas).
  El overscan de la tanda 3 (la cámara alejando hasta 0.82 y dibujando 1.5× de área) ya no
  existe desde la corrida 1.
- **Al CERRAR la corrida 4 de la tanda 4, mismo aparejo y Spotify parado: 17-39% de un core,
  media 27%** (26.2 y 27.9 las dos corridas). Baja un tercio contra el baseline de arriba y
  **la causa NO está medida**: esta corrida no optimizó nada — la arena recorre más lejos
  (`ZMAX` 16 → 34), el hiperespacio pasó de 46 items a 110 y la carta de ajuste AGREGÓ un
  Canvas. Los sospechosos son el estado del aparejo y que el baseline se tomó con el
  `dunes.frag` a medio hacer del worker anterior cargado. Antes de festejar la baja, medir de
  nuevo con el mismo `cpu-bench.py` en frío.
- **Corrida 5 (túnel de verdad), mismo aparejo, Spotify parado: 22-39% de un core, media 30%**
  (29.3 y 30.6 las dos corridas). Sube ~3 puntos contra el cierre de la corrida 4: el sospechoso
  es que el túnel ahora evalúa la pared DOS veces (el barrido del drop), y es uno de los tres
  motivos que el aparejo fuerza. Es el número vigente; falta re-medirlo en frío sin el aparejo
  forzando motivos caros (pendiente, ver abajo).
- El análisis de audio es Python puro sobre `pw-record` (sin cava, sin numpy): 0.79% de CPU.
  Arma el mapa del tema por percentil de energía dentro de la propia canción
  (quiet/verse/build/drop) y lo cachea: la segunda vez que suena, anticipa los golpes.
