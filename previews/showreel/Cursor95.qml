// fatal-lyrics showreel — la flecha de Win95 (blanca con borde negro).
import QtQuick

Canvas {
    id: c
    property real k: 1
    width: 13 * k
    height: 21 * k
    onKChanged: requestPaint()
    onPaint: {
        const g = getContext("2d");
        g.reset();
        g.scale(width / 13, height / 21);
        g.beginPath();
        g.moveTo(0.5, 0.5); g.lineTo(0.5, 17); g.lineTo(4.5, 13); g.lineTo(7.2, 19.5);
        g.lineTo(9.6, 18.4); g.lineTo(7, 12.2); g.lineTo(12, 12.2); g.closePath();
        g.fillStyle = "#ffffff"; g.fill();
        g.lineWidth = 1; g.strokeStyle = "#000000"; g.stroke();
    }
}
