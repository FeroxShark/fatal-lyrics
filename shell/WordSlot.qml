// fatal-lyrics — la palabra del director: entra, tipea (si toca) y se asienta.
//
// Extraído de Crt.qml (tanda 6, corrida 6, paso 1): antes vivía inline en el
// `Repeater` del director. No lee `crt`, `measure` ni ningún otro id de
// Crt.qml — ids no cruzan de archivo — así que todo lo que necesita entra por
// propiedad, seteada por quien instancia este componente.
import QtQuick

Item {
    id: slot

    required property int index
    required property string word
    // lo calcula quien instancia (necesita `reveal`/`dueFrac`/`burnStep`,
    // que viven en `crt` y no cruzan de archivo)
    property bool landed: false
    // tanda 6, corrida 6, paso 2: "typed|hard|burn|soft|none". Sin uso todavía.
    property string emphasis: "none"
    property var pal: ({ ink: "#e0e0e0", hot: "#ffffff" })
    property string fontFamily: ""
    property real letterSpacing: 3
    property real pixelSize: 24
    // == ctl.crtWordFlash
    property real flash: 0
    property string entryStyle: "snap"
    // fin de la animación de entrada, palabra ya asentada
    signal settled()
    // overburn quema TODA la pantalla, no sólo esta palabra: el `burnGlow`
    // vive en `crt`, así que el que la instancia decide qué hacer
    signal overburnHit()

    width: parent ? parent.width : label.implicitWidth
    height: label.implicitHeight * 0.88

    // T3.5, estilo "type": la palabra no aparece, se escribe — un caracter
    // cada 28 ms, con el cursor pegado atrás mientras dura. Se cuenta por code
    // point y no por unidad UTF-16, si no un caracter japonés se escribe en
    // dos mitades rotas.
    readonly property int chars: Array.from(word).length
    property int typed: 0
    Timer {
        interval: 28
        repeat: true
        running: slot.entryStyle === "type" && slot.landed
            && slot.typed < slot.chars
        onTriggered: slot.typed++
    }

    opacity: landed ? 1 : 0

    transform: [
        Scale { id: sc; origin.x: slot.width / 2; origin.y: slot.height / 2 },
        Translate { id: tr }
    ]

    Text {
        id: label
        anchors.horizontalCenter: parent.horizontalCenter
        text: slot.entryStyle !== "type"
            ? slot.word.toUpperCase()
            : Array.from(slot.word.toUpperCase())
                .slice(0, slot.typed).join("")
                + (slot.typed < slot.chars ? "▮" : "")
        color: slot.pal.ink
        // la letra acompaña al fondo: si el fondo se lava en un segundo y la
        // tinta salta de golpe, el salto de la tinta es el flash. (Las
        // animaciones de entrada no pasan por acá: un Behavior no intercepta
        // lo que anima otro.)
        Behavior on color { ColorAnimation { duration: 900; easing.type: Easing.InOutQuad } }
        font.family: slot.fontFamily
        font.bold: true
        font.letterSpacing: slot.letterSpacing
        font.pixelSize: slot.pixelSize
    }

    // fantasmas de canal desalineado: sólo mientras entra
    Text {
        x: label.x - slot.ghostOff
        text: label.text
        font: label.font
        color: "#ff2d00"
        opacity: slot.ghostFade * 0.55
    }
    Text {
        x: label.x + slot.ghostOff
        text: label.text
        font: label.font
        color: "#00c8ff"
        opacity: slot.ghostFade * 0.55
    }
    property real ghostOff: 0
    property real ghostFade: 0

    onLandedChanged: {
        if (landed) {
            typed = 0;
            entry.restart();
        }
    }

    // La entrada: la palabra llega como si el televisor recién la
    // sintonizara. El destello de color tiene su propia perilla
    // (`word_flash`) porque pasa en CADA palabra — con el destello a full se
    // lee como que la letra titila todo el tiempo, y no es lo mismo que el
    // latido del tubo.
    readonly property color entryTint: slot.entryStyle === "overburn"
        // sobrequemada: blanco puro, pase lo que pase con `word_flash` — es
        // lo que define la entrada
        ? "#ffffff"
        : slot.flash <= 0.01
        ? slot.pal.ink
        // proporción directa: el piso de 0.25 que tenía hacía que hasta en el
        // mínimo la palabra entrara clarita, y el mínimo tiene que ser "nada"
        : Qt.tint(slot.pal.ink, Qt.rgba(1, 1, 1, slot.flash))

    SequentialAnimation {
        id: entry
        ScriptAction {
            script: if (slot.entryStyle === "overburn")
                slot.overburnHit();
        }
        PropertyAction { target: label; property: "color"; value: slot.entryTint }
        // TODO el sacudón de entrada va por la misma perilla, no sólo el
        // color: los fantasmas de canal y el tirón de tamaño pasan igual en
        // cada palabra, así que con el destello apagado seguían leyéndose
        // como que la letra vibra. `word_flash = 0` es la palabra entrando
        // quieta.
        PropertyAction { target: slot; property: "ghostOff"; value: slot.pixelSize * (slot.entryStyle === "roll" ? 0.34 : 0.22) * slot.flash }
        PropertyAction { target: slot; property: "ghostFade"; value: 0.85 * slot.flash }
        PropertyAction { target: sc; property: "xScale"; value: 1 + (slot.entryStyle === "slam" ? 0.35 : 0.06) * slot.flash }
        PropertyAction { target: sc; property: "yScale"; value: 1 + (slot.entryStyle === "slam" ? 0.35 : -0.18) * slot.flash }
        PropertyAction { target: tr; property: "y"; value: slot.entryStyle === "roll" ? -slot.pixelSize * 0.55 * slot.flash : 0 }
        PauseAnimation { duration: 28 }
        // T4.3: TODAS las palabras entran con la misma gramática — snap
        // `OutExpo` y asentamiento visible (`Motion.enterMs`). Antes eran
        // 90 ms de OutQuad con la `y` en OutBack y el estilo `slam` en 150:
        // tres curvas distintas para el mismo gesto, y a 90 ms el
        // asentamiento no existe — la palabra aparece y ya está, que es justo
        // lo contrario del video de referencia (el primer cuadro recorre la
        // mitad del camino y los últimos tres son imperceptibles). `slam` y
        // `roll` conservan su AMPLITUD, que es lo que los hace distintos; la
        // curva es una.
        ParallelAnimation {
            // el blanco del overburn baja despacio: es una quemadura del
            // fósforo, no un destello
            ColorAnimation { target: label; property: "color"; to: slot.pal.ink; duration: slot.entryStyle === "overburn" ? 200 : Motion.enterFastMs; easing.type: Easing.OutQuad }
            NumberAnimation { target: sc; property: "xScale"; to: 1; duration: Motion.enterMs; easing.type: Easing.OutExpo }
            NumberAnimation { target: sc; property: "yScale"; to: 1; duration: Motion.enterMs; easing.type: Easing.OutExpo }
            NumberAnimation { target: tr; property: "y"; to: 0; duration: Motion.enterMs; easing.type: Easing.OutExpo }
            // los fantasmas de canal son la SALIDA del gesto: se van rápido
            // para no competir con el asentamiento de la palabra
            NumberAnimation { target: slot; property: "ghostOff"; to: 0; duration: Motion.exitMs; easing.type: Easing.OutExpo }
            NumberAnimation { target: slot; property: "ghostFade"; to: 0; duration: Motion.exitMs; easing.type: Easing.InQuad }
            SequentialAnimation {
                NumberAnimation { target: tr; property: "x"; from: -slot.pixelSize * 0.07 * slot.flash; to: slot.pixelSize * 0.03 * slot.flash; duration: 34 }
                NumberAnimation { target: tr; property: "x"; to: 0; duration: Motion.enterFastMs; easing.type: Easing.OutExpo }
            }
        }
        // la animación de color rompe el binding; hay que devolvérselo o la
        // palabra se queda con el color viejo cuando la pantalla se contagia
        // otro
        ScriptAction {
            script: label.color = Qt.binding(() => slot.pal.ink);
        }
        ScriptAction {
            script: slot.settled();
        }
    }
}
