#version 440
// fatal-lyrics — motivo `swarm`, vértices: UNA instancia por flecha (o por estela, o por
// las que escriben) armada en la placa, sin geometría por cuadro.
//
// Truco: el `GridMesh` de 4159 × 1 celdas es una tira de 4160 columnas × 2 filas; cada
// instancia usa 4 columnas consecutivas (c0: la esquina de arriba-izquierda en las dos filas;
// c1: arriba-izquierda y abajo-izquierda; c2: arriba-derecha y abajo-derecha; c3: la de
// abajo-derecha en las dos filas). Sólo la celda (c1, c2) tiene área; las otras tres (y la que
// une una instancia con la siguiente) quedan colapsadas sobre dos puntos y no dibujan nada.
// Una instancia que no corresponde (id ≥ count, o no es de este bloque) colapsa entera.
//
// 4 bloques de 260 instancias, en orden de dibujo: estela 2, estela 1, flechas del fondo
// (con su clic), las que escriben. El id es la profundidad (4 tandas por tramos del id, de
// atrás para adelante, como las tandas del Shape viejo); las que escriben se reparten parejo
// entre todos los ids (Bresenham), así el fondo no pierde una sola profundidad.
//
// Todo es analítico y periódico en 15 s (la misma `wander` que tenía Swarm.qml en JS, con
// otro hash: ya no tiene que coincidir con el de `Ease.js`, nadie lo compara).
//
// Build:  /usr/lib/qt6/bin/qsb --glsl '100 es,120,150' -o swarm.vert.qsb swarm.vert
// (swarm.frag lleva el MISMO bloque de uniforms: si tocás uno, tocá el otro)

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;

layout(location = 0) out vec4 vLocal;   // xy: píxel respecto del origen de la flecha; z: px por casilla; w: radio del anillo (px)
layout(location = 1) out vec4 vFill;
layout(location = 2) out vec4 vStroke;
layout(location = 3) out vec4 vRing;
layout(location = 4) out vec4 vP;       // x: grosor del trazo (px); y: grosor del anillo (px)

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

const float TAU = 6.2831853;
const float NSLOT = 260.0;

float hash(float n) {
    float p = fract((n + 7.13) * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}
float hash2(float a, float b) { return hash(a * 57.0 + b * 131.0); }

// ruido 1D que se repite cada P unidades (P entero)
float pnoise(float x, float P, float s) {
    float i = floor(x);
    float f = x - i;
    float u = f * f * (3.0 - 2.0 * f);
    float a = mod(i, P), b = mod(i + 1.0, P);
    return mix(hash(a + s * 91.7), hash(b + s * 91.7), u) * 2.0 - 1.0;
}

float outExpo(float x) { return x >= 1.0 ? 1.0 : 1.0 - pow(2.0, -10.0 * x); }
float prog(float t, float t0, float dur) { return clamp((t - t0) / dur, 0.0, 1.0); }

// dónde está la flecha `i` de la bandada en el instante `tt`
vec2 wander(float i, float tt) {
    float fl = mod(i, flocks);
    float u = tt / 15.0;
    float cx = res.x * 0.5 + res.x * 0.34 * pnoise(u * 3.0 + fl * 0.31, 3.0, 1.0 + sd + fl * 5.0);
    float cy = res.y * 0.5 + res.y * 0.30 * pnoise(u * 3.0 + 0.5 + fl * 0.17, 3.0, 2.0 + sd + fl * 7.0);
    float ang = hash(i * 1.7) * TAU + TAU * u * (mod(fl, 2.0) > 0.5 ? -1.0 : 1.0);
    float rad = span * spread * (0.05 + 0.17 * sqrt(hash(i * 2.3 + 1.0)))
              * (1.0 + 0.25 * sin(TAU * u * 2.0 + fl));
    return vec2(cx + cos(ang) * rad * 1.35 + span * 0.03 * pnoise(u * 5.0 + i * 0.37, 5.0, i * 1.3),
                cy + sin(ang) * rad + span * 0.03 * pnoise(u * 5.0 + i * 0.61, 5.0, i * 2.1 + 7.0));
}

// el punto `j` de la palabra, empaquetado (x * 8 + y)
#define PICK(P) P[int(cc)][int(rr)]
float ptAt(float j) {
    float mi = floor(j / 16.0);
    float r16 = j - mi * 16.0;
    float rr = floor(r16 / 4.0);
    float cc = r16 - rr * 4.0;
    return mi < 0.5 ? PICK(p0) : mi < 1.5 ? PICK(p1) : mi < 2.5 ? PICK(p2) : mi < 3.5 ? PICK(p3)
         : mi < 4.5 ? PICK(p4) : mi < 5.5 ? PICK(p5) : mi < 6.5 ? PICK(p6) : mi < 7.5 ? PICK(p7)
         : mi < 8.5 ? PICK(p8) : mi < 9.5 ? PICK(p9) : mi < 10.5 ? PICK(p10) : mi < 11.5 ? PICK(p11)
         : mi < 12.5 ? PICK(p12) : mi < 13.5 ? PICK(p13) : mi < 14.5 ? PICK(p14) : mi < 15.5 ? PICK(p15)
         : mi < 16.5 ? PICK(p16) : PICK(p17);
}

void main() {
    float col = floor(qt_MultiTexCoord0.x * 4159.0 + 0.5);
    float row = step(0.5, qt_MultiTexCoord0.y);
    float inst = floor(col / 4.0);
    float c = col - inst * 4.0;
    float blk = floor(inst / NSLOT);
    float id = inst - blk * NSLOT;
    float cu = step(1.5, c);
    float cv = c < 0.5 ? 0.0 : (c > 2.5 ? 1.0 : row);

    // ¿escribe? Bresenham: j = cuántas escriben antes que ella
    float wj = floor(id * writers / count);
    float isW = floor((id + 1.0) * writers / count) - wj;
    bool live = id < count && (blk > 2.5 ? isW > 0.5 : isW < 0.5);

    vec2 org = vec2(0.0);
    float sc = 1.0, sw = 0.0, ringR = 0.0, rw = 1.0;
    vec4 fillC = vec4(0.0), strokeC = vec4(0.0), ringC = vec4(0.0);

    if (live && blk < 2.5) {
        // las del fondo: tanda (profundidad) por tramos del id
        float tier = min(3.0, floor(4.0 * id / count));
        float dp = (tier + 0.5) / 4.0;
        sc = arrow * (0.55 + 0.7 * dp);
        float a0 = min(1.0, 0.22 + 0.5 * dp + 0.2 * dropAmt + 0.15 * beatHot);
        if (blk < 0.5) {            // estela 2
            org = wander(id, lt - 0.09);
            fillC = vec4(ink.rgb, a0 * 0.09);
        } else if (blk < 1.5) {     // estela 1
            org = wander(id, lt - 0.045);
            fillC = vec4(ink.rgb, a0 * 0.18);
        } else {
            org = wander(id, lt);
            sw = max(1.0, sc * 0.7);
            bool front = dp > 0.6;
            strokeC = vec4(front ? hot.rgb : dark.rgb, front ? 0.5 * a0 : 0.8);
            fillC = vec4(ink.rgb, a0);
            // el clic del tiempo
            if (bp < 1.0 && hash2(id, clickSeed) * count < clickN) {
                ringR = sc * (4.0 + 22.0 * outExpo(bp));
                rw = max(1.0, sc * 1.1);
                ringC = vec4(dropOn > 0.5 ? hot.rgb : ink.rgb, 0.7 * (1.0 - bp) * (0.5 + 0.5 * dp));
            }
        }
    } else if (live) {
        // las que escriben
        sc = arrow;
        float need1 = max(1.0, need);
        float pt = ptAt(mod(wj, need1));
        float px = floor(pt / 8.0);
        float py = pt - px * 8.0;
        float k = floor(wj / need1);
        float gx = ox + (px + 0.12 + 0.34 * k) * cell;
        float gy = oy + (py + 0.08 + 0.30 * k) * cell;
        float wcx = ox + cols * cell * 0.5, wcy = oy + 3.5 * cell;
        float stag = (px / max(1.0, cols)) * 0.12;
        float f, burst = 0.0;
        if (q < 3.0) {
            f = outExpo(prog(q * bs, stag, 0.32));
        } else {
            float e = outExpo(prog((q - 3.0) * bs, stag * 0.5, 0.42));
            f = 1.0 - e;
            burst = sin(3.14159265 * e) * span * 0.16;
        }
        vec2 w = wander(id, lt);
        float tx = gx + (gx - wcx) * swell, ty = gy + (gy - wcy) * swell;
        float st = floor(lt * 30.0 + 1e-6);
        tx += (hash2(wj, st) - 0.5) * shake;
        ty += (hash2(wj + 91.0, st) - 0.5) * shake;
        float dx = gx - wcx, dy = gy - wcy, dl = max(1.0, sqrt(dx * dx + dy * dy));
        org = mix(w, vec2(tx, ty), f) + vec2(dx, dy) / dl * burst;
        // 5 tandas según cuánto llegó
        float lit = floor((f > 0.9 ? 1.0 : f) * 4.0 + 0.5) / 4.0;
        sw = max(1.0, arrow * 0.8);
        strokeC = vec4(lit > 0.9 ? hot.rgb : dark.rgb, 0.5 + 0.5 * lit);
        fillC = vec4(beatHot > 0.3 ? hot.rgb : ink.rgb, 0.35 + 0.65 * lit);
    }

    // la caja: la flecha (grilla de 12 × 19) y, si hay, el anillo; 1 px de aire
    vec2 lo = org - vec2(sw + 1.0), hi = org + vec2(11.4, 18.0) * sc + vec2(sw + 1.0);
    if (ringR > 0.0) {
        lo = min(lo, org - vec2(ringR + rw + 1.0));
        hi = max(hi, org + vec2(ringR + rw + 1.0));
    }
    vec2 pos = live ? mix(lo, hi, vec2(cu, cv)) : vec2(0.0);

    vLocal = vec4(pos - org, sc, ringR);
    vFill = fillC;
    vStroke = strokeC;
    vRing = ringC;
    vP = vec4(sw, rw, 0.0, 0.0);
    gl_Position = qt_Matrix * vec4(pos, 0.0, 1.0);
}
