# cartelitos — Cómo pensarlo: dos procesos, config con hot-reload, interruptor del CRT, línea siguiente, salto, motivos, entradas, sync, foco y idioma de la letra

Movido textual desde `CLAUDE.md` (2026-10-07). Las tres REGLAS (una animación por pantalla, `Motion.qml`, `pace`) siguen en `CLAUDE.md`.

- **Dos procesos, no uno.** Un daemon de Python (busca la letra, la sincroniza, la manda) y un
  overlay de Quickshell (la dibuja). Se hablan por un socket Unix. Cualquier diagnóstico tiene que
  mirar **los dos PIDs**: `fatal status` distingue ON / HALF / OFF justamente porque el daemon
  vivo con el overlay muerto es un estado real y frecuente.
- **La config es un TOML con hot-reload**, no un wizard. `~/.config/cartelitos/config.toml` viaja
  del daemon al overlay por el socket; el daemon vigila el mtime y aplica en vivo. Nada necesita
  `fatal restart`. Un TOML roto conserva la config anterior.
  **Todas las opciones están en la ventana de Ajustes** (`fatal ajustes`, `shell/settings.qml`):
  cinco pestañas, cada cambio se aplica al tocarlo, "Undo changes" vuelve a como estaba al abrir.
  `fatal config` / `fatal setup` abren la misma ventana. Hubo un menú de terminal (`setup.py`,
  y antes un wizard lineal de 24 preguntas); Ferox lo sacó (2026-10-09): **no volver a abrir
  opciones en una terminal**. Lo único que queda sólo en el TOML es `[system] not_a_game`.
- **El interruptor del CRT es un ARCHIVO**, no el socket: `$XDG_RUNTIME_DIR/cartelitos-crt`, que
  el QML vigila. Así apaga aunque el daemon esté colgado.
- **El tubo sabe dónde va a caer la línea SIGUIENTE.** El daemon manda una línea por vez, así que
  el `show` viaja con `next` (`{text, t0, t1, segs}`, o `null`) y hay un evento `lyrics` con la
  letra entera del tema. Con eso el overlay calcula el reparto de la línea k+1 mientras suena la k
  y lo **consume** cuando llega: la anticipación es la verdad, no un pronóstico. De ahí salen el
  motif que huye (`foreshadow`) y el aro que cuenta (`ring`, `shell/Ring.qml`). Con el `next`
  viaja también el `due` — cuándo va a salir el próximo `show`, con el offset del daemon ya
  descontado — y con el `show`, el `v_end` de la línea que suena.
- **El salto de la frase se ve viajar, y ESA es la flecha.** Cuando la línea cae en otra pantalla,
  la perilla `hop` (`corridor|interference|both|off`) manda un rayo: nace como hebras estiradas de
  la letra que se va, cruza cada pantalla del medio POR EL BORDE (arriba o abajo, alternando) y
  converge al centro de la de destino, encima de la línea que llega. Cabeza brillante y cola, color
  degradado origen→destino. Un solo reloj lo publica (`shell.qml`, `crtHopStart`) y cada monitor lo
  lee. **El rayo es lo que dice DÓNDE va a caer la letra** — textual de Ferox: "me gusta la línea
  glitchada que indica 'tu ojo va a ir para acá', esa antes que un timer". El aro no señala nada:
  avisa que vuelve la voz.
- **Una pantalla sin letra no dibuja cualquier cosa: dibuja algo del tema.** Los motivos leen lo
  que el tubo ya sabe (la letra que viene, el ritmo, el drop, el compás). `dunes` es el único paisaje:
  quieto, la cámara se mueve. `eyes` es UN ojo mirando a la pantalla que tiene la frase. Qué lee cada
  uno: `docs/TRAMPAS.md` ("Detalle movido: motivos y set").
- **Cómo entra la línea lo decide la música, no un sorteo parejo.** `crtEntriesFor` reparte UN
  estilo de entrada por pantalla al consumir la línea, pesado por el nivel de los últimos ~2 s y
  por la parte del tema (tabla `crtEntryTable` en `shell.qml`, con el comentario de cómo tunearla).
  Se sumaron `interlace` (medio cuadro, uniform del shader), `tubeon` (punto → raya → imagen, el
  apagado al revés) y `overburn` (cada palabra quemada en blanco, sólo en un drop con compás
  confiable). La cámara además sigue la sección (`section_zoom`): lejos en la estrofa, encima en el
  drop.
- **El sync a ojo aprende por TEMA antes que por artista.** `fatal sync +/-` corrige el
  tema que suena de una; el offset se le guarda al ARTISTA recién cuando dos temas distintos
  suyos pidieron lo mismo (`offsets.record(artist, delta, track_id)`). Se guarda el PROMEDIO
  de los que votaron (no la suma) y a ellos se les descuenta (rebase): el tema que suena no salta. Se mira y se borra con
  `fatal sync show` / `fatal sync reset [<artista>|all]`, que no necesitan el daemon.
- **En el CRT la letra no se clona.** Hay una pantalla enfocada, la frase sigue en la de al lado y
  el pedazo ya leído queda quemado abajo. Las repeticiones se cortan en el daemon
  (`split_repeats`) y cada golpe cae en otra pantalla. `focus = "all"` vuelve al comportamiento
  viejo.
- **La letra va en el idioma en que se canta.** Cadena de proveedores (`lrclib` exacto →
  `lrclib` búsqueda → `NetEase`), título original y después el limpio, gana el primer `ok`.
  De NetEase `lrc`, **nunca** `tlyric` (traducción al chino). Ningún campo de traducción.
