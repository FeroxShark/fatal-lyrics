"""Tanda 50: costo del tubo y del overlay. Pruebas de cableado sobre el QML (nadie corre Qt acá):
cada una fija una decisión que, si se pierde, vuelve el gasto sin que nada se rompa a la vista."""
import os
import re
import unittest

SHELL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shell")


def read(name):
    with open(os.path.join(SHELL, name), encoding="utf-8") as f:
        return f.read()


class TuboRendimiento(unittest.TestCase):
    def setUp(self):
        self.crt = read("Crt.qml")
        self.root = read("shell.qml")

    def test_tubo_apagado_frena_reloj_textura_y_estela(self):
        # r1.1: oscuro Y con el nivel en 0 no se ve más que el 3 % de ruido
        self.assertRegex(self.crt, r"readonly property bool tubeIdle:\s*tubeDark && tubeLevel < 0\.01")
        frame = re.search(r"FrameAnimation \{\s*running:(.*?)onTriggered", self.crt, re.S).group(1)
        self.assertIn("!crt.tubeIdle", frame)
        timer = re.search(r"interval: crt\.deepSleep \|\| crt\.tubeIdle.*?running:(.*?)\n", self.crt, re.S).group(1)
        self.assertIn("crt.tubeIdle", timer)
        gate = re.search(r"readonly property bool trailOn:(.*?)\n    on", self.crt, re.S).group(1)
        self.assertIn("!tubeIdle", gate)
        self.assertEqual(len(re.findall(r"live: crt\.visible && !crt\.tubeIdle", self.crt)), 2)
        # el vidrio NO se oculta: el ruido de fósforo del tubo apagado es lo único que se ve
        self.assertRegex(self.crt, r"id: glass\s+anchors\.fill: parent\s+visible: crt\.visible\n")

    def test_estatica_del_standby_se_duerme_al_minuto(self):
        # r1.2: se baja el plazo, no la tasa (el zumbido de 60 Hz se aliasearía)
        m = re.search(r"Timer \{\s*interval: (\d+)\s*running: crt\.visible && crt\.standby && !crt\.deepSleep", self.crt)
        self.assertIsNotNone(m)
        self.assertLessEqual(int(m.group(1)), 60000)

    def test_poll_de_la_letra_no_corre_en_reposo(self):
        # r1.3
        poll = re.search(r"interval: crt\.reveal < 1 \? 33 : 80.*?running:([^\n]*)", self.crt, re.S).group(1)
        self.assertIn("!crt.resting", poll)

    def test_dirt_sin_behavior_con_audio_vivo(self):
        # r3.1: ~25 aud/s ya suavizados; un Behavior encima nunca termina
        self.assertRegex(self.root, r"Behavior on crtDirt \{ enabled: !root\.audLive;")

    def test_un_solo_pump_para_la_pared(self):
        # r3.2: el Timer vive en el root; la pantalla lo lee mientras no esté en reposo
        self.assertRegex(self.root, r"property real crtPump:")
        self.assertRegex(self.root, r"crtRestingCount < root\.activeCrtScreens\.length")
        self.assertRegex(self.crt, r'Binding \{ target: crt; property: "pump"; value: crt\.ctl\.crtPump; when: crt\.visible && !crt\.resting \}')
        self.assertNotRegex(self.crt, r"crt\.pump = ")
        self.assertNotRegex(self.crt, r"Behavior on pump")
        self.assertIn("ctl.crtRestingCount += resting ? 1 : -1", self.crt)

    def test_despertar_del_deepsleep_con_puente(self):
        # r21.3: la estática vuelve en Motion.bridgeMs, no de golpe
        self.assertRegex(self.crt, r"property real sleepMix: deepSleep \? 0 : 1")
        self.assertRegex(self.crt, r"Behavior on sleepMix \{ NumberAnimation \{ duration: Motion\.bridgeMs;")
        noise = re.search(r"property real noiseAmt:(.*?)property real tubeLevel", self.crt, re.S).group(1)
        self.assertIn("crt.sleepMix", noise)
        self.assertNotIn("crt.deepSleep ? 0", noise)


if __name__ == "__main__":
    unittest.main()
