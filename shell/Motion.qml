// fatal-lyrics — el lenguaje de movimiento del tubo, en un solo lugar.
//
// El video de referencia que pasó Ferox (`docs/plans/2026-09-04-fluidez-referencia.md`)
// no es fluido por tener más cuadros: es fluido porque TODO se mueve con la
// misma gramática. Una entrada pega un snap y se asienta (`OutExpo`), una
// salida se va rápido (`InQuad`), la cámara paneó y después se queda quieta, y
// entre evento y evento hay un hold largo. Hoy cada animación del tubo tiene su
// número inventado (70, 90, 150, 220, 260, 350, 420, 900) y por eso la pared
// entera se lee como ruido: no hay dos cosas que entren igual.
//
// Acá viven esos números y NADA más. Un `Behavior` que quiera otra duración
// tiene que justificar por qué su movimiento no es ninguno de estos cinco.
//
// Es un singleton de Quickshell: `pragma Singleton` + el tipo `Singleton`, y se
// usa por el nombre del archivo (`Motion.enterMs`), sin instanciarlo.
pragma Singleton
import Quickshell

Singleton {
    // ---- entradas: snap y asentamiento. El primer cuadro recorre la mitad del
    // camino y los últimos son casi imperceptibles. Nunca lineal, nunca
    // `InOutQuad`: eso arranca despacio y se lee como algo que se arrastra.
    readonly property int enterMs: 320          // easing.type: Easing.OutExpo
    // la versión corta, para lo que entra encima de otra cosa que ya está
    // pasando (el número del aro, el puente entre dos dibujos)
    readonly property int enterFastMs: 120      // Easing.OutExpo

    // ---- salidas: rápidas o corte seco. Lo que se va no tiene que competir
    // con lo que entra.
    readonly property int exitMs: 140           // Easing.InQuad

    // ---- la cámara: un solo movimiento por cambio de sección, y después
    // quieta salvo la deriva.
    readonly property int cameraMs: 520         // Easing.OutExpo

    // ---- apagar/prender un dibujo entero (el `dim` del motif)
    readonly property int dimMs: 220

    // ---- el hold: mínimo que algo se queda quieto antes de que pase la cosa
    // siguiente. No es una duración de animación: es el presupuesto.
    readonly property int holdMs: 1500

    // ---- el glitch PUENTE: dos o tres cuadros entre una escena y la otra. Es
    // el piso de 120 ms de la tanda 3 (nada visible dura menos), y también el
    // techo: un puente que se ve como efecto dejó de ser un puente.
    readonly property int bridgeMs: 120
}
