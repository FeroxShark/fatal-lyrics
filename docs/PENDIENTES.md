# cartelitos — Pendientes

Backlog vivo. Leerlo al planear una tanda.
Movido tal cual desde `CLAUDE.md` el 2026-09-05.

**Tanda 6 (hecha 2026-09-16, falta que Ferox la mire con música):** set por tema + mazos,
fuente por tema, mood, secciones que apagan pantallas, intro de tema, palabra con énfasis,
eventos raros. De la tanda 5 absorbió los puntos 3 y 5; **1 (`stars`), 2 (`dunes`), 4 (zooms)
y 6 (círculo aburrido) siguen abiertos.**

- **Mood sesgado por volumen:** `mood.energy()` usa el rms medido post-fader (`pw-record`
  sobre el monitor del sink), así que un tema escuchado bajito da "tranquilo". Opciones:
  compensar con el volumen del sink (no ve el volumen propio de la app) o medir dinámica
  relativa dentro del tema.

- **AUR:** `packaging/` listo y probado. Falta que Ferox cree cuenta en aur.archlinux.org y
  registre su clave SSH (1Password); después clonar
  `ssh://aur@aur.archlinux.org/fatal-lyrics-git.git`, copiar `packaging/` y push.
- **CPU del overlay: falta re-medir en frío.** Todos los números de "Números medidos" de acá en
  más se toman con el mismo aparejo de `cpu-bench.py` — motivos caros (tunnel/rorschach/ekg)
  forzados en las tres pantallas y un verso cada 2 s —, que es el TECHO, no el uso normal.
  Nunca se corrió con música de verdad, sin forzar nada, para saber el número que Ferox va a ver
  la mayor parte del tiempo.
- README: falta la captura del menú de bandeja y la de `fatal config`. Receta del GIF:
  `wf-recorder -o <salida>` + ffmpeg `palettegen(max_colors=96)` / `paletteuse`. No hay gifsicle.
- **La tanda 4 quedó COMPLETA** (`docs/plans/2026-09-04-crt-tanda4.md`,
  `docs/plans/2026-09-04-estado-tras-tanda4.md`): corrida 1 (sacar el overscan), 2 (el aro es un
  cronómetro exacto), 2b (el aro sólo avisa instrumental, la flecha es el rayo), 3 (lenguaje de
  movimiento y perilla `pace`), 4-pre (`fatal crt motif`, para dejar de pescar con palabras
  clave), 4 (ojos/dunes/testcard), 4b (la burbuja se parte, la aguja de la carta de ajuste, el
  mar) y 5 (el túnel se dobla, dovelas, niebla, luz que corre). Lo que falta mirar a ojo con
  música de verdad está en `docs/plans/CHECKS-VISUALES.md`, secciones "TANDA 4 corrida …".
  Decisiones abiertas para Ferox (no tocar sin su OK): qué motifs "feos" sacar del pool por
  default (`stars` en cara oscura, `dunes`/`textsea`/`testcard` en la auditoría de la corrida 3,
  ya mejorados en la 4 — falta que Ferox los vea con música), el fondo del túnel en las paletas
  invertidas (queda claro, no negro: dos alternativas probadas y documentadas en
  `tunnel.frag`), si la burbuja de `plasma` va más ovalada/huevo (bajar la compuerta del vidrio
  en `plasma.frag`) y qué tan seguido se parte con el grave real, y si el alcance del campo de
  `stars` (factor `1.05` en `Motif.qml:549`) necesita subir.
- **La tanda 3 quedó COMPLETA** (`docs/plans/2026-09-04-crt-tanda3-feedback.md`): la corrida 1
  fue A1 (el overscan de los motivos), A2 (un `Loader` solo), A3 (el encuadre y el plano de la
  sección), A4 (la boca del túnel) y B7; la 2 fue A5 (una animación por pantalla), B1 (el aro que
  se desarma), B10 (el aro que come al ritmo), B2 (las familias de la mancha), B3 (los ojos),
  B4 (el rayo del salto), B8 (el contraste del túnel), B9 (el piso del cardiograma), B5 (el IOWN
  anclado) y B6 (el piso de 120 ms); la 3 fue C (el sync a ojo: la regla por temas, el rótulo
  del tubo, `fatal sync show|reset` y las perillas `[keys]`). Lo que se miró con capturas y lo
  que todavía necesita un ojo está en `docs/plans/CHECKS-VISUALES.md`, secciones "TANDA 3
  corrida 1", "corrida 2" y "corrida 3".
- **El plan `docs/plans/2026-09-03-crt-tanda2.md` quedó COMPLETO** (FASE 0 a FASE 5): foco
  anticipado, aviso de destino (`foreshadow`/`ring`), saltos entre pantallas (`hop`), entradas
  nuevas + director por energía, y ocho motifs nuevos. Estado y mapa actualizado en
  `docs/plans/2026-09-03-estado-tras-tanda2.md`; lo que falta mirar a ojo está en
  `docs/plans/CHECKS-VISUALES.md` (nadie lo vio prendido con música todavía).
- **El plan de mejoras `docs/plans/2026-09-03-mejoras-fatal-lyrics.md` quedó COMPLETO** (FASE 0 a
  FASE 5). Falta probarlo cantando: el modo karaoke (`fatal sing on`) se verificó con la captura
  del micrófono andando y con los tests del `SingGate`, pero nadie cantó todavía — si el umbral
  quedó duro o blando, se toca `SING_ON`/`SING_OFF` en `cartelitos/daemon.py`.
