#version 440
// fatal-lyrics — motivo `swarm`, píxeles: el puntero de Windows 95 (polígono de 7 vértices
// en su grilla de 12 × 19, relleno + borde) y el anillo del clic, con borde analítico de 1 px.
// Lo dibuja encima de la cara, premultiplicado. Los vértices (swarm.vert) ya dejaron todo en
// `vLocal`/`vFill`/`vStroke`/`vRing`: acá no hay más que formas.
//
// Build:  /usr/lib/qt6/bin/qsb --glsl '100 es,120,150' -o swarm.frag.qsb swarm.frag
// (swarm.vert lleva el MISMO bloque de uniforms: si tocás uno, tocá el otro)

layout(location = 0) in vec4 vLocal;
layout(location = 1) in vec4 vFill;
layout(location = 2) in vec4 vStroke;
layout(location = 3) in vec4 vRing;
layout(location = 4) in vec4 vP;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // la palabra, empaquetada: cada punto encendido = x * 8 + y (x < 48, y < 7), 16 por matriz
    // (fila = t / 4, columna = t % 4: `Qt.matrix4x4` recibe filas y el shader lee columnas)
    mat4 p0;
    mat4 p1;
    mat4 p2;
    mat4 p3;
    mat4 p4;
    mat4 p5;
    mat4 p6;
    mat4 p7;
    mat4 p8;
    mat4 p9;
    mat4 p10;
    mat4 p11;
    mat4 p12;
    mat4 p13;
    mat4 p14;
    mat4 p15;
    mat4 p16;
    mat4 p17;
    vec4 ink;         // fósforo (`colour`)
    vec4 hot;
    vec4 dark;        // el borde de las del fondo (`bg` más oscuro)
    vec2 res;         // píxeles
    float span;       // lado corto
    float lt;         // fase del loop (0..15)
    float sd;         // la semilla de la aparición, chica (el hash en float32 no aguanta números grandes)
    float flocks;     // bandadas (2..4)
    float spread;
    float count;      // flechas (≤ 260)
    float writers;    // las que escriben la palabra
    float need;       // puntos de la palabra
    float cols;       // columnas de la palabra
    float cell;       // lado de la casilla de la palabra (px)
    float ox;
    float oy;
    float arrow;      // escala (px por casilla de la grilla 12x19) de las que escriben
    float q;          // dónde va del compás, en tiempos (0..4)
    float bs;         // segundos por tiempo
    float bp;         // cuánto va del tiempo (0..1)
    float beatHot;    // el golpe del tiempo en el drop
    float swell;      // la palabra late
    float dropAmt;
    float dropOn;     // 0 / 1
    float shake;      // cuánto tiembla cada puntero (px): la subida
    float clickN;     // cuántas hacen clic en este tiempo
    float clickSeed;
};

// la flecha: (0,0) (0,16) (4,12) (7,18) (9.4,17) (6.4,11) (11.4,11) y vuelve al (0,0)
float seg(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}
// el borde que cruza el rayo horizontal hacia +x (paridad par-impar)
float cross_(vec2 p, vec2 a, vec2 b) {
    bool span_ = (a.y > p.y) != (b.y > p.y);
    float x = a.x + (p.y - a.y) * (b.x - a.x) / (span_ ? (b.y - a.y) : 1.0);
    return (span_ && x > p.x) ? 1.0 : 0.0;
}

void main() {
    float s = vLocal.z;
    vec2 p = vLocal.xy / s;           // grilla de la flecha
    const vec2 v0 = vec2(0.0, 0.0), v1 = vec2(0.0, 16.0), v2 = vec2(4.0, 12.0), v3 = vec2(7.0, 18.0),
               v4 = vec2(9.4, 17.0), v5 = vec2(6.4, 11.0), v6 = vec2(11.4, 11.0);
    float d = seg(p, v0, v1);
    d = min(d, seg(p, v1, v2));
    d = min(d, seg(p, v2, v3));
    d = min(d, seg(p, v3, v4));
    d = min(d, seg(p, v4, v5));
    d = min(d, seg(p, v5, v6));
    d = min(d, seg(p, v6, v0));
    float n = cross_(p, v0, v1) + cross_(p, v1, v2) + cross_(p, v2, v3) + cross_(p, v3, v4)
            + cross_(p, v4, v5) + cross_(p, v5, v6) + cross_(p, v6, v0);
    float inside = mod(n, 2.0);
    float dpx = d * s;                // distancia al borde en píxeles
    float covF = clamp(0.5 + (inside > 0.5 ? dpx : -dpx), 0.0, 1.0);
    float covS = vP.x > 0.0 ? clamp(vP.x * 0.5 + 0.5 - dpx, 0.0, 1.0) : 0.0;

    float aF = vFill.a * covF, aS = vStroke.a * covS;
    vec4 o = vec4(vStroke.rgb * aS, aS) + vec4(vFill.rgb * aF, aF) * (1.0 - aS);

    if (vLocal.w > 0.0) {
        float dr = abs(length(vLocal.xy) - vLocal.w);
        float aR = vRing.a * clamp(vP.y * 0.5 + 0.5 - dr, 0.0, 1.0);
        o = vec4(vRing.rgb * aR, aR) + o * (1.0 - aR);
    }
    fragColor = o * qt_Opacity;
}
