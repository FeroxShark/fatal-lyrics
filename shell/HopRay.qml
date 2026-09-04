// fatal-lyrics — el rayo del salto.
//
// Cuando la frase salta a una pantalla que no es la de al lado, esto es el
// viaje. La primera versión era una franja pareja de scanlines cruzando por el
// medio de cada pantalla intermedia, dibujada en `crt.frag`: Ferox la vio poco
// y le pareció una distracción, porque cruzaba justo por encima del motivo de
// la pantalla del medio y no decía hacia dónde iba.
//
// El recorrido de ahora (lo describió Ferox, T3.B4):
//   · de la LETRA de la pantalla de origen se estiran unas hebras, que salen
//     por el borde hacia el lado del viaje,
//   · en la pantalla del medio agarran por el BORDE, arriba o abajo (alternando
//     salto a salto), sin pasar nunca por el centro: ahí abajo hay un motivo y
//     la regla A5 dice que no se superpone nada,
//   · en la de destino convergen al centro, donde está por caer la letra, y se
//     apagan encima de ella.
//
// Tiene cabeza y cola, no ancho parejo: una cabeza brillante y una estela que
// se apaga se lee como una flecha, y una flecha se entiende de un vistazo. El
// color va del de la letra que se va al de la letra que llega, repartido a lo
// largo de TODO el viaje: cada pantalla pinta su tramo del degradado, así que
// la pared entera es un solo gradiente aunque cada monitor dibuje por su lado.
//
// El reloj es del root (`crtHopStart`): acá sólo se lee. Con un reloj por
// monitor la cabeza entra en la segunda pantalla antes de salir de la primera.
import QtQuick

Item {
    id: ray

    // "from" | "mid" | "to"
    property string role: "mid"
    property int dir: 1               // +1 el viaje va a la derecha
    property real progress: 0         // 0..1 dentro de ESTA pantalla
    property real globalFrom: 0       // dónde empieza este tramo del viaje
    property real globalTo: 1         // y dónde termina: para el degradado
    property real fade: 1             // la cola en el destino, apagándose
    property bool edgeTop: true       // por qué borde cruza la intermedia
    property color colFrom: "#4fe8ff"
    property color colTo: "#ffd6de"
    // alto del bloque de texto, 0..1 de la pantalla: de ahí nacen las hebras
    property real textH: 0.34

    readonly property int strands: 3
    readonly property real tailU: 0.42     // largo de la cola, en u

    onProgressChanged: canvas.requestPaint()
    onFadeChanged: canvas.requestPaint()

    function lerp(a, b, f) { return a + (b - a) * f; }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative

        // El color en un punto del viaje. `g` es el avance GLOBAL, no el de
        // esta pantalla: es lo que hace que las tres pantallas pinten tramos
        // distintos del mismo degradado.
        function shade(g, a) {
            const f = Math.max(0, Math.min(g, 1));
            return Qt.rgba(ray.lerp(ray.colFrom.r, ray.colTo.r, f),
                           ray.lerp(ray.colFrom.g, ray.colTo.g, f),
                           ray.lerp(ray.colFrom.b, ray.colTo.b, f), a);
        }

        // El recorrido de una hebra, en coordenadas 0..1 de la pantalla. `k` es
        // cuál de las hebras: se separan en el eje que no manda el viaje, así
        // que salen como un manojo y no como una línea sola.
        function at(u, k) {
            const spread = (k - (ray.strands - 1) / 2) / Math.max(ray.strands, 1);
            const ey = ray.edgeTop ? 0.09 : 0.91;
            if (ray.role === "from") {
                // nacen del alto del texto y se van estirando hacia el borde
                const y0 = 0.5 + spread * ray.textH;
                const e = u * u * (3 - 2 * u);
                return [0.5 + ray.dir * u * 0.62 + spread * 0.04,
                        ray.lerp(y0, ey, e)];
            }
            if (ray.role === "mid") {
                // por el borde, sin acercarse al centro
                return [ray.dir > 0 ? -0.08 + 1.16 * u : 1.08 - 1.16 * u,
                        ey + spread * 0.05 + 0.012 * Math.sin(u * 9 + k)];
            }
            // destino: entra por el borde y converge al medio
            const e = u * u * (3 - 2 * u);
            const x0 = ray.dir > 0 ? -0.08 : 1.08;
            return [ray.lerp(x0, 0.5, e) + spread * 0.03 * (1 - e),
                    ray.lerp(ey, 0.5, e * e) + spread * 0.06 * (1 - e)];
        }

        onPaint: {
            const c = getContext("2d");
            c.reset();
            if (ray.progress <= 0 || ray.fade <= 0.01)
                return;
            const w = width, h = height;
            const side = Math.min(w, h);
            const lw = Math.max(3, side * 0.010);
            c.lineCap = "round";

            const steps = 9;
            for (let k = 0; k < ray.strands; k++) {
                // cada hebra va un poco atrás de la anterior: el manojo se
                // estira, que es lo que hace que se lea la dirección
                // en el origen y en el medio la cabeza se deja pasar del borde:
                // si se clavara en 1, la cola quedaría pegada al canto de la
                // pantalla en vez de salir
                const pMax = ray.role === "to" ? 1 : 1.45;
                const p = Math.max(0, Math.min(ray.progress - k * 0.05, pMax));
                if (p <= 0)
                    continue;
                const u0 = Math.max(0, p - ray.tailU);
                for (let i = 0; i < steps; i++) {
                    const ua = u0 + (p - u0) * (i / steps);
                    const ub = u0 + (p - u0) * ((i + 1) / steps);
                    const f = (i + 1) / steps;            // 0 cola, 1 cabeza
                    const A = at(ua, k), B = at(ub, k);
                    const g = ray.lerp(ray.globalFrom, ray.globalTo, ub);
                    c.beginPath();
                    c.moveTo(A[0] * w, A[1] * h);
                    c.lineTo(B[0] * w, B[1] * h);
                    // dos pasadas: una ancha y floja que es el halo del fósforo
                    // y una fina encima. Con una sola el rayo se leía como un
                    // pelo puesto sobre el tubo.
                    c.strokeStyle = shade(g, f * f * 0.22 * ray.fade);
                    c.lineWidth = lw * (1.2 + 2.2 * f);
                    c.stroke();
                    c.strokeStyle = shade(g, f * f * ray.fade);
                    c.lineWidth = lw * (0.35 + 0.65 * f);
                    c.stroke();
                }
                // la cabeza: un punto brillante, que es lo que el ojo sigue
                const H = at(p, k);
                const gh = ray.lerp(ray.globalFrom, ray.globalTo, p);
                const hc = shade(gh, 1);
                c.fillStyle = Qt.rgba(Math.min(hc.r + 0.45, 1),
                                      Math.min(hc.g + 0.45, 1),
                                      Math.min(hc.b + 0.45, 1),
                                      0.95 * ray.fade);
                const r = lw * 1.15;
                c.beginPath();
                c.ellipse(H[0] * w - r, H[1] * h - r, r * 2, r * 2);
                c.fill();
            }
        }
    }
}
