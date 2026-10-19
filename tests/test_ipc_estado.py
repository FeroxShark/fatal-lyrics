"""IPC: el estado del tema sobrevive a la reconexión del overlay, un rebobinado
no borra la letra, `sec`/`cue` no se tiran y el primer evento tras reiniciar el
overlay no se pierde (tanda IPC). Con un socket Unix de verdad en un tmp."""
import atexit
import json
import os
import socket
import sys
import tempfile
import threading
import unittest
from unittest import mock

_TMP = tempfile.TemporaryDirectory()
atexit.register(_TMP.cleanup)
os.environ["XDG_CONFIG_HOME"] = os.path.join(_TMP.name, "config")
os.environ["XDG_CACHE_HOME"] = os.path.join(_TMP.name, "cache")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from cartelitos import ipc  # noqa: E402


class Overlay:
    """Un 'overlay' de mentira: acepta una conexión y junta los eventos."""

    def __init__(self, path):
        self.path = path
        self.srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.srv.bind(path)
        self.srv.listen(1)
        self.conn = None

    def accept(self):
        self.srv.settimeout(2)
        self.conn, _ = self.srv.accept()
        self.conn.settimeout(0.3)

    def events(self):
        buf = b""
        try:
            while True:
                chunk = self.conn.recv(65536)
                if not chunk:
                    break
                buf += chunk
        except socket.timeout:
            pass
        return [json.loads(ln) for ln in buf.splitlines() if ln]

    def restart(self):
        """Muere el overlay y vuelve uno nuevo en el mismo path."""
        self.conn.close()
        self.srv.close()
        os.unlink(self.path)
        self.__init__(self.path)

    def close(self):
        for s in (self.conn, self.srv):
            if s:
                s.close()


class IpcCase(unittest.TestCase):
    def setUp(self):
        self.path = os.path.join(_TMP.name, "t.sock")
        if os.path.exists(self.path):
            os.unlink(self.path)
        p = mock.patch.object(ipc, "SOCK_PATH", self.path)
        p.start()
        self.addCleanup(p.stop)
        self.reset()
        self.addCleanup(self.reset)
        self.ov = Overlay(self.path)
        self.addCleanup(self.ov.close)

    @staticmethod
    def reset():
        if ipc._sock is not None:
            ipc._sock.close()
        ipc._sock = None
        ipc._last_np = None
        ipc._last_lyrics = None
        ipc._track_state.clear()
        ipc._dead_until = 0.0
        ipc._fail_count = 0

    def connect(self):
        ipc.send({"cmd": "pos", "p": 1, "l": 100})
        self.ov.accept()
        return self.ov.events()

    def cmds(self, evs):
        return [e["cmd"] for e in evs]


class TestEstadoAlReconectar(IpcCase):
    def test_art_mood_sec_char_sing_vuelven_despues_de_la_letra(self):
        self.connect()
        ipc.lyrics_list([(0.0, "a"), (4.0, "b")])
        ipc.send({"cmd": "art", "id": "t1", "colors": ["#fff"]})
        ipc.send({"cmd": "mood", "valence": 0.3})
        ipc.send({"cmd": "sec", "kind": "chorus", "p": 0.8})
        ipc.send({"cmd": "char", "v": 0.7})
        ipc.send({"cmd": "sing", "on": True})
        self.ov.events()
        self.ov.restart()
        ipc.send({"cmd": "pos", "p": 2, "l": 100})
        self.ov.accept()
        evs = self.ov.events()
        cmds = self.cmds(evs)
        self.assertEqual(cmds[0], "config")
        self.assertLess(cmds.index("lyrics"), cmds.index("art"))
        for c in ("art", "mood", "sec", "char", "sing"):
            self.assertIn(c, cmds)
        self.assertEqual(next(e for e in evs if e["cmd"] == "art")["id"], "t1")

    def test_un_tema_nuevo_suelta_el_estado_del_anterior_menos_sing(self):
        self.connect()
        ipc.send({"cmd": "art", "id": "t1", "colors": ["#fff"]})
        ipc.send({"cmd": "mood", "valence": 0.3})
        ipc.send({"cmd": "sing", "on": True})
        ipc.clear(why="track", track_id="t2")
        self.assertEqual(set(ipc._track_state), {"sing"})

    def test_un_rebobinado_conserva_letra_y_estado(self):
        self.connect()
        ipc.lyrics_list([(0.0, "a"), (4.0, "b")])
        ipc.send({"cmd": "mood", "valence": 0.3})
        ipc.clear(why="seek")
        self.assertIsNotNone(ipc._last_lyrics)
        self.assertIn("mood", ipc._track_state)
        ipc.clear(why="pause")
        self.assertIsNotNone(ipc._last_lyrics)

    def test_un_tema_nuevo_suelta_la_letra(self):
        self.connect()
        ipc.lyrics_list([(0.0, "a")])
        ipc.clear(why="track", track_id="t2")
        self.assertIsNone(ipc._last_lyrics)
        ipc.clear()
        self.assertIsNone(ipc._last_lyrics)


class TestSendSoft(IpcCase):
    def test_sec_y_cue_esperan_el_lock_en_vez_de_perderse(self):
        self.connect()
        self.ov.events()
        ipc._send_lock.acquire()
        res = []
        t = threading.Thread(target=lambda: res.append(
            ipc.send_soft({"cmd": "sec", "kind": "chorus", "p": 0.5})))
        t.start()
        t.join(0.2)
        self.assertTrue(t.is_alive())      # esperando, no descartó
        ipc._send_lock.release()
        t.join(2)
        self.assertEqual(res, [True])
        self.assertEqual(self.cmds(self.ov.events()), ["sec"])

    def test_el_resto_se_descarta_con_el_lock_tomado(self):
        self.connect()
        self.ov.events()
        with ipc._send_lock:
            self.assertFalse(ipc.send_soft({"cmd": "wave", "l": 0, "r": 0}))
        self.assertEqual(self.ov.events(), [])


class TestPrimerEventoTrasReiniciar(IpcCase):
    def test_el_evento_que_fallaba_con_epipe_llega(self):
        self.connect()
        self.ov.restart()
        ipc.send({"cmd": "show", "text": "hola", "title": "t"})
        self.ov.accept()
        evs = self.ov.events()
        self.assertEqual(self.cmds(evs)[0], "config")
        self.assertEqual(self.cmds(evs)[-1], "show")

    def test_overlay_muerto_sigue_sin_colgar_y_activa_el_backoff(self):
        self.connect()
        self.ov.restart()
        self.ov.close()
        os.unlink(self.path) if os.path.exists(self.path) else None
        ipc.send({"cmd": "show", "text": "a", "title": "t"})
        ipc.send({"cmd": "show", "text": "b", "title": "t"})
        self.assertIsNone(ipc._sock)
        self.assertGreater(ipc._dead_until, 0.0)


if __name__ == "__main__":
    unittest.main()
