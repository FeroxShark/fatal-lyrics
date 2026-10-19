"""Ningún shell/*.qml asigna la misma propiedad o handler dos veces en el mismo objeto.

Ferox 2026-10-19: un merge dejó dos `onNoLyricChanged:` en el objeto raíz de Crt.qml, el overlay
no cargó ("Property value set multiple times") y los 1002 tests pasaban. qmllint no lo ve: sólo
marca `width: 1; width: 2` (duplicate-property-binding), no los handlers. Por eso esto es un
parser mínimo: quita comentarios, strings, templates y regex; sigue las llaves; los bloques JS
no cuentan; cada objeto y cada grupo (`anchors { }`) tiene su propio conjunto de claves."""
import glob
import os
import re
import unittest

SHELL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shell")

# `nombre:` al inicio de una sentencia (`on…` incluido). Las declaraciones (`property int x: 1`,
# `function f(a: T)`) no matchean: tienen un espacio antes de los dos puntos.
CLAVE = re.compile(r"\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*:(?!:)")
# Lo que precede a un `{` que abre un objeto QML: un tipo (`Item`, `Quickshell.Io.Process`,
# `property T x: Tipo`, `states: [ State`) o un grupo (`anchors`, `Behavior on opacity`).
# Cualquier otra cosa (`onX: {`, `if (a) {`, `else {`, `=> {`) es bloque JS.
OBJETO = [
    re.compile(r"(?:^|[\s\[,(])[A-Z][\w.]*$"),
    re.compile(r"(?:^|[\s\[,(])(?!(?:else|try|finally|do|return)\b)[a-z_]\w*$"),
]
# Si una línea termina en uno de estos, la sentencia sigue en la próxima.
CONTINUA = "?:,+-*/%&|=!<>.(["
# Caracteres tras los que un `/` abre una regex y no una división.
ANTES_REGEX = "(,=:[!&|?{};+-*%<>~^"


def _blanco(s):
    return re.sub(r"[^\n]", " ", s)


def _fin_cadena(src, i):
    q = src[i]
    j = i + 1
    while j < len(src) and src[j] != q:
        j += 2 if src[j] == "\\" else 1
    return min(j, len(src))


def _fin_regex(src, i):
    j, clase = i + 1, False
    while j < len(src) and src[j] != "\n":
        c = src[j]
        if c == "\\":
            j += 2
            continue
        if clase:
            clase = c != "]"
        elif c == "[":
            clase = True
        elif c == "/":
            return j
        j += 1
    return j


def _limpiar(src):
    """Blanquea comentarios, strings, templates y regex. Conserva saltos de línea y comillas."""
    out, i, n, ultimo = [], 0, len(src), ""
    while i < n:
        c = src[i]
        if src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
            continue
        if src.startswith("/*", i):
            j = src.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(_blanco(src[i:j]))
            i = j
            continue
        if c in "\"'`":
            j = _fin_cadena(src, i)
            out.append(c + _blanco(src[i + 1:j]) + (c if j < n else ""))
            i, ultimo = j + 1, c
            continue
        if c == "/" and (ultimo == "" or ultimo in ANTES_REGEX):
            j = _fin_regex(src, i)
            if j < n and src[j] == "/":
                out.append("/" + _blanco(src[i + 1:j]) + "/")
                i, ultimo = j + 1, "/"
                continue
        out.append(c)
        if not c.isspace():
            ultimo = c
        i += 1
    return "".join(out)


def _es_objeto(cabecera):
    cab = cabecera.rstrip()
    return any(r.search(cab) for r in OBJETO)


def _cierre_js(src, i):
    """`i` queda después de un `{` de bloque JS; devuelve el índice después de su `}`."""
    prof = 1
    while i < len(src):
        if src[i] == "{":
            prof += 1
        elif src[i] == "}":
            prof -= 1
            if not prof:
                return i + 1
        i += 1
    return i


def _continua(buf):
    s = "".join(buf).rstrip()
    return bool(s) and s[-1] in CONTINUA


def _objeto(src, i, dups):
    """`i` queda después de un `{` de objeto; devuelve el índice después de su `}` (o el fin).
    Anota en `dups` (pos, clave, pos_primera) cada clave que aparece dos veces en este objeto."""
    vistos, buf, ini, par, n = {}, [], i, 0, len(src)

    def cerrar():
        s = "".join(buf)
        m = CLAVE.match(s)
        if not m:
            return
        pos = ini + len(s) - len(s.lstrip())
        clave = m.group(1)
        if clave in vistos:
            dups.append((pos, clave, vistos[clave]))
        else:
            vistos[clave] = pos

    while i < n:
        c = src[i]
        if c == "{":
            cabecera = "".join(buf)
            buf.append("{}")
            if _es_objeto(cabecera):
                i = _objeto(src, i + 1, dups)
            else:
                i = _cierre_js(src, i + 1)
            continue
        if c == "}":
            cerrar()
            return i + 1
        if c in "([":
            par += 1
        elif c in ")]":
            par = max(0, par - 1)
        if (c == ";" and par == 0) or (c == "\n" and par == 0 and not _continua(buf)):
            cerrar()
            buf, ini = [], i + 1
        else:
            buf.append(" " if c == "\n" else c)
        i += 1
    cerrar()
    return n


def duplicados(src):
    """[(linea, clave, linea_primera)] de las claves asignadas dos veces en un mismo objeto QML."""
    limpio = _limpiar(src)
    crudos = []
    _objeto(limpio, 0, crudos)
    return [(limpio.count("\n", 0, pos) + 1, clave, limpio.count("\n", 0, prim) + 1)
            for pos, clave, prim in crudos]


def _archivos():
    return sorted(glob.glob(os.path.join(SHELL, "*.qml")))


class DuplicadosQML(unittest.TestCase):
    def test_los_shell_qml_no_repiten_asignaciones(self):
        archivos = _archivos()
        self.assertTrue(archivos, "no hay shell/*.qml: el test quedaría vacío")
        fallas = []
        for ruta in archivos:
            with open(ruta, encoding="utf-8") as f:
                for linea, clave, primera in duplicados(f.read()):
                    fallas.append("%s:%d: %s (ya estaba en la línea %d)"
                                  % (os.path.basename(ruta), linea, clave, primera))
        self.assertFalse(fallas, "asignación repetida en el mismo objeto "
                                 "(Property value set multiple times):\n" + "\n".join(fallas))

    def test_detecta_handler_repetido_en_la_raiz(self):
        src = ("import QtQuick\n"
               "PanelWindow {\n"
               "    property bool noLyric: false\n"
               "    onNoLyricChanged: {\n"
               "        if (noLyric) a();\n"
               "    }\n"
               "    onNoLyricChanged: { }\n"
               "}\n")
        self.assertEqual(duplicados(src), [(7, "onNoLyricChanged", 4)])

    def test_detecta_propiedad_repetida_en_un_grupo_y_en_un_hijo(self):
        src = ("Item {\n"
               "    anchors { left: a; left: b }\n"
               "    Rectangle { width: 1; width: 2 }\n"
               "}\n")
        self.assertEqual(duplicados(src), [(2, "left", 2), (3, "width", 3)])

    def test_objetos_distintos_y_bloques_js_no_chocan(self):
        src = ("Item {\n"
               "    width: 1\n"
               "    Item { width: 2 }\n"
               "    text: cond\n"
               "        ? a\n"
               "        : b\n"
               "    onX: {\n"
               "        var o = { a: 1, a: 2 };\n"
               "        switch (k) { case 1: f(); case 2: g(); }\n"
               "        var t = p ?\n"
               "            q : r;\n"
               "    }\n"
               "    onY: f(\"width: 1\", /[\"]x/.test(s) ? 1 : 2)\n"
               "    // width: 9\n"
               "    /* width: 9 */\n"
               "}\n")
        self.assertEqual(duplicados(src), [])


if __name__ == "__main__":
    unittest.main()
