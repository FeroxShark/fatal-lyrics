// fatal-lyrics — banco del ritmo de los dibujos (tanda 8, slice movimiento-visual),
// fuera de pantalla.
//
// Una pantalla sin letra con el `Mystify` REAL de `shell/` (deriva por `lt`, el reloj
// de dibujo de `MotifBase`), sin el vidrio: lo que se mide es la fase del dibujo, no
// el tubo. El reloj es `t`, que lo avanza `render.py` cuadro a cuadro; `mov` lo pone
// la partitura del mismo `render.py`. El ritmo sale de `shell/Speed.js` — la MISMA
// función que llama el overlay —, con la fila de `crtPaceTable` que lee render.py.
//
// Ronda 3: el golpe empuja la velocidad. `render.py` pone `hitT`/`hitStrength` y sube
// `hitN`; el empujón lo calculan `Speed.kickAdd`/`Speed.kickAt` (las MISMAS que el
// overlay) y entra en el `rate` que integra `Speed.advance`.
//
// `mode`:
//   · "int"  — como el overlay: `movOff += dt · (rate − 1)` (`Speed.advance`)
//   · "prod" — el control, lo que NO hay que hacer: `movOff = t · (rate − 1)`, o sea
//              reloj de dibujo `t · rate`
//   · "off"  — la perilla en 0: ritmo 1, lo de antes
// En los tres, `clock` es `t` (el reloj real): el compás y el repintado de
// `MotifBase` lo siguen leyendo igual.
import QtQuick
import "../../shell"
import "../../shell/Speed.js" as Speed

Item {
    id: stage
    width: 1280
    height: 720

    property real t: 0
    property real mov: 0
    property string mode: "int"
    property var pace: ({ movMin: 0.75, movMax: 1.35, movKick: 0.5 })

    // el golpe: `render.py` pone tiempo y fuerza y sube `hitN`
    property real hitT: 0
    property real hitStrength: 0
    property int hitN: 0
    property real kickV0: 0
    property real kickT: -1e6
    onHitNChanged: {
        kickV0 = Speed.kickAdd(Speed.kickAt(kickV0, hitT - kickT), hitStrength, pace.movKick);
        kickT = hitT;
    }
    readonly property real kick: Speed.kickAt(kickV0, t - kickT)
    readonly property real baseRate: mode === "off" ? 1 : Speed.rate(mov, pace.movMin, pace.movMax, 1)
    readonly property real rate: mode === "off" ? 1 : Speed.push(baseRate, kick, 1)
    // el mismo número, con el reloj `tt` a mano: en `onTChanged` el binding de `kick`
    // todavía puede tener el `t` viejo, y el integrador tiene que leer el del cuadro
    function rateAt(tt) {
        return mode === "off" ? 1 : Speed.push(baseRate, Speed.kickAt(kickV0, tt - kickT), 1);
    }
    property real movOff: 0
    property real lastT: -1
    // lo que lee render.py: el reloj de dibujo sin envolver (`lt` es esto mod 15)
    readonly property real drawT: t + movOff

    function reset() {
        movOff = 0;
        lastT = -1;
        kickV0 = 0;
        kickT = -1e6;
        m.tickAt = -1e6;
        m.paintedAt = -1e6;
    }

    // `clock` se asigna DESPUÉS del desplazamiento: el motivo repinta en
    // `onClockChanged`, y con un binding a `t` podía pintar con el `movOff` viejo
    onTChanged: {
        if (mode === "prod")
            movOff = t * (rateAt(t) - 1);
        else if (mode === "int" && lastT >= 0)
            movOff = Speed.advance(movOff, t - lastT, rateAt(t));
        lastT = t;
        m.clock = t;
    }

    Rectangle { anchors.fill: parent; color: "#04162e" }

    Mystify {
        id: m
        anchors.fill: parent
        tubeClock: -1
        movOff: stage.movOff
        rate: stage.rate
        colour: "#7fe4ff"
        hot: "#ffffff"
        bg: "#04162e"
        seed: 0.37
        energy: 1.2
    }
}
