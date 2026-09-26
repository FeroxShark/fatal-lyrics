# cartelitos — Pendientes

Backlog vivo. Leerlo al planear una tanda.
Movido tal cual desde `CLAUDE.md` el 2026-09-05.

**Tanda 7 (hecha 2026-09-26, estado en `docs/plans/2026-09-25-estado-tras-tanda7.md`):** señal compuesta,
tubos, estela, tensión, quemado del estribillo, glitch al beat, efectos por palabra, intro v2 con carta, osciloscopio
real, estática por suciedad, reposo en pausa. Todo medido con aparejo sintético; **nada visto con música real.** Abierto:

- **Calibrar `dirt` con música real.** `FLAT_LO/HI` 0.10/0.45 (`audio.py`) y `dirtMax` 2/3/4.5 (`crtPaceTable`) salieron de
  tonos, ruido y voz TTS. Con un tema de guitarras distorsionadas y uno limpio, mirar el campo `d` de `aud` y ajustar.
- **Validar a ojo los rangos de tensión** (`tensionMin/Max` de `crtPaceTable`: calm 0.92–1.12, normal 0.80–1.30, wild
  0.60–1.70): la captura de la corrida 4a no fue concluyente. `crt.tension = 0` la apaga.
- **Reloj a 60 por `Timer`** en vez de `FrameAnimation` (con `frameSwapped` para `frameAvgMs`): el tope de 60 fps en
  `tubeTime` no baja `normal` (~33 %) porque la animación sigue al refresco nativo (144/120/60).
- Mirar con música: composite 0.5, estela (cara clara y `composite=1`), quemado (contraste 4.1–4.5 % a 0.5),
  beat lock, efectos por palabra y la carta de la intro (`docs/plans/CHECKS-VISUALES.md`).
- Decisiones de Ferox: `crt.tube` (`custom` de siempre, `auto` o `trinitron` fijo), default de `crtQuality`.
- SIGSEGV en el driver nvidia (`QRhi::beginFrame`, 2 casos en la corrida 6, sin repro): si vuelve, seguir en TRAMPAS.

**Tanda 6 (hecha 2026-09-16, falta que Ferox la mire con música):** set por tema + mazos,
fuente por tema, mood, secciones que apagan pantallas, intro de tema, palabra con énfasis,
eventos raros. De la tanda 5 absorbió los puntos 3 y 5; **1 (`stars`), 2 (`dunes`), 4 (zooms)
y 6 (círculo aburrido) siguen abiertos.**

- **Mood sesgado por volumen — RESUELTO 2026-09-16.** `audio.py` guarda ahora la ganancia
  efectiva de captura (`TrackProfile.gain`, `_capture_gain()`: stream de la app, más el sink
  sólo si NO tiene `HW_VOLUME_CTRL` — medido que si lo tiene, el sink se aplica en hardware
  después de donde `pw-record` engancha el monitor, así que su volumen no afecta el rms
  capturado). `mood.energy()` divide el rms por esa ganancia antes de compararlo contra
  FLOOR/CEIL, reescalados por `ENERGY_GAIN_REF` (docs/NUMEROS-MEDIDOS.md). Perfiles viejos sin
  `gain` guardado siguen el camino de siempre, sin reescalar nada — quedan como estaban, no se
  puede saber a qué ganancia se midieron. Pendiente menor: el blend entre escuchadas
  (`PROFILE_BLEND_OLD/NEW`) promedia rms de sesiones a volúmenes distintos sin ponderar por
  gain — con perfiles ya normalizados esto pesa mucho menos que antes, no se tocó.

- **AUR:** `packaging/` listo y probado. Falta que Ferox cree cuenta en aur.archlinux.org y
  registre su clave SSH (1Password); después clonar
  `ssh://aur@aur.archlinux.org/fatal-lyrics-git.git`, copiar `packaging/` y push.
- ~~CPU del overlay: re-medir en frío~~ **cerrado** en la tanda 7, corrida 8 (`docs/NUMEROS-MEDIDOS.md`, "Frío"):
  `normal` ~33 %, `pausa` 25 -> 16 % con el reposo. Sigue sin haber música real en el aparejo (sintético).
  Seguimiento abierto: el tope de 60 fps no baja el `normal` (la `FrameAnimation` sigue al refresco nativo);
  si se quiere bajar de verdad, reloj a 60 por `Timer` en vez de `FrameAnimation`, con `frameSwapped` para `frameAvgMs`.
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
