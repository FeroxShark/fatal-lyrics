# Tanda 8 — slice "sigue"

Bug reportado: en el motivo `splitflap` (placa de casilleros, título "FATAL LYRICS" /
"VERSO n/m") la fila de abajo siempre dice "SIGUE:" y nunca muestra nada después.

## Texto chiquito ("MOVE THE MOUSE TO RETURN")

NO es parte del bug. Es el rótulo de salida del tubo (`shell/Crt.qml:2493`, item `hint`),
a propósito casi invisible (`opacity: 0.08` en reposo). Funciona como se diseñó. Descartado.

## Causa real (confirmada leyendo el código, no sólo la captura)

`shell/Splitflap.qml` arma el cartel en la property `board`. Encontré DOS problemas en el
mismo bloque:

1. **La fila SIGUE (el bug reportado):** `out.push(pad("SIGUE: " + D.clean(nextWord), ...))`
   usa `nextWord` a secas. Esa prop llega de `crt.ctl.crtNextWord` (`shell.qml`), que sale de
   `crtNext.text` — y `crtNext` sólo se llena cuando el DAEMON manda un `show()` con `nxt=`
   (`cartelitos/daemon.py:370`). Para una letra SIN sincronizar (`lyrics_kind == "plain"`,
   común: `lrclib`/NetEase muchas veces sólo tienen el texto plano, no LRC por palabra) el
   daemon manda un ÚNICO `show()` sin `nxt` (`cartelitos/ipc.py:253`, default `nxt=None`) y
   nunca más — `crtNext` queda `null` TODO el tema. Lo mismo pasa en el hueco entre que
   llega el evento `lyrics` (letra entera) y el primer `show()` de una letra sincronizada
   (arranque del tema): ahí tampoco hay `nextWord` todavía aunque la letra completa ya se
   conoce. En ninguno de los dos casos había fallback: la fila quedaba con la etiqueta y
   nada atrás — justo la promesa vacía que pide NO dejar.
2. **Bug hermano en la misma property (no reportado, lo encontré al leer el código):** la fila
   del VERSO (`const text = ... D.clean(lines[lineNo % nl])`) le pasa a `D.clean` el OBJETO
   `{t0,t1,text,rep}` entero en vez de `.text` (confirmado el shape correcto contra
   `shell/TextSea.qml:113`, que sí hace `row.modelData.text`). Con letra sincronizada activa
   esa fila mostraría basura (`D.clean` stringifica el objeto letra por letra). No se ve en
   la captura de Ferox porque ahí `lineNo` ya era `-1` (título "FATAL LYRICS"), pero es la
   misma clase de bug ("campo mal nombrado") en el mismo archivo, así que lo arreglé de una.
   `Swarm.qml` tiene el MISMO patrón (`D.clean(lines[lineNo % lines.length])`) — NO LO TOQUÉ
   (no es el motivo del reporte, ni la causa de este bug); si en algún momento se ve
   `[OBJECT...]` en el motivo swarm con letra real, es este mismo bug ahí.

## Qué debía ir después de "SIGUE:"

Diseño (comentario del propio archivo, línea 11): "la primera palabra de la línea que
viene". Coincide con cómo lo usa `Swarm.qml` (que arma la palabra letra por letra en su
propia grilla). Elegí esa misma definición para el fallback.

## Fix

`shell/Splitflap.qml` (+ su copia `previews/crt-motifs/motifs/Splitflap.qml`, sólo difieren
en los imports, ver CLAUDE.md):

- Función `lineText(entry)`: soporta tanto el shape real (`{text}`) como el string plano que
  usa el arnés sintético de `previews/crt-motifs` (no le tocué la data de prueba).
- Fila de verso: `D.clean(lineText(lines[lineNo % nl]))` en vez de pasar el objeto entero.
- Fila SIGUE: si `nextWord` (lo que mandó el daemon) está vacío, se adelanta con la primera
  palabra de la línea `lineNo+1` (o la 0 si `lineNo < 0`) sacada de `lines`, que ya se conoce
  aunque el daemon no haya mandado `next` todavía. Si TAMPOCO hay eso (letra sin sincronizar
  Y sin líneas, o no hay letra), la fila queda en blanco sin la etiqueta — nunca "SIGUE:"
  solo. `pad("", cols, false)` en vez de forzar el prefijo.

## Test

`tests/test_cartelitos.py`, clase nueva `TestSplitflapNextWord` (usa `node` para evaluar el
JS real extraído de `board`, mismo patrón que `test_tension_curve_values`). Casos:
normal (nextWord llega), letra sin sincronizar (nextWord vacío, hay `lines`), arranque de
tema (lineNo=-1, hay `lines`), sin nada (lines=[]) → fila vacía sin "SIGUE:".
`@unittest.skipUnless(shutil.which("node"), ...)`.

## Estado

- [x] Diagnóstico.
- [ ] Fix en `shell/Splitflap.qml` + copia en previews.
- [ ] Test que falla antes / pasa después.
- [ ] Correr suite completa.

## Cómo retomar

Si se corta acá: falta escribir el fix (arriba está el plan exacto) y el test. No hace
falta más lectura de código, ya está todo rastreado línea por línea.
