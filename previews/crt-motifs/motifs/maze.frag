#version 440
// fatal-lyrics — motivo `maze`: el "Laberinto 3D" de Windows 95 en fósforo.
//
// Raycaster por píxel (DDA por la grilla, como el Wolfenstein de la época):
// paredes con ladrillo y aristas encendidas, piso con cuadrícula que se pierde
// en la niebla, techo oscuro. El laberinto es un ANILLO de pasillo (x 1..9,
// y 1..7) con nichos y pasillos ciegos a los costados sembrados con `seed`: la
// cámara da la vuelta entera en 32 tiempos y el loop cierra solo. Dónde está la
// cámara lo decide Maze.qml; acá sólo se dibuja.
//
// Build:  /usr/lib/qt6/bin/qsb --glsl '100 es,120,150' -o maze.frag.qsb maze.frag
// Sin fwidth (GLSL 100 es no lo trae sin extensión): el ancho de una línea en
// unidades de mundo sale de la distancia, que es lo que fwidth daría acá.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;         // píxeles
    vec3 cam;         // x, y (celdas) y ángulo (rad)
    float bob;        // el paso: la cámara sube y baja un poco (fracción de alto)
    float pulse;      // 0..1 el golpe del tiempo: aristas en `hot`
    float dropAmt;    // 0..1 drop: la niebla se abre y el piso se enciende
    float fogK;       // cuánta niebla (1/celdas)
    float seed;
    float lt;         // reloj del loop (0..15): lo único que corre solo
    vec4 ink;
    vec4 hot;
    vec4 bg;
};

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// distancia de la celda al anillo (0 = pasillo del anillo)
float ringDist(vec2 c) {
    if (c.x >= 1.0 && c.x <= 9.0 && c.y >= 1.0 && c.y <= 7.0)
        return min(min(c.x - 1.0, 9.0 - c.x), min(c.y - 1.0, 7.0 - c.y));
    return max(max(1.0 - c.x, c.x - 9.0), max(1.0 - c.y, c.y - 7.0));
}

// hacia dónde queda el anillo desde `c` (para los pasillos ciegos de 2)
vec2 towardRing(vec2 c) {
    if (c.x < 1.0) return vec2(1.0, 0.0);
    if (c.x > 9.0) return vec2(-1.0, 0.0);
    if (c.y < 1.0) return vec2(0.0, 1.0);
    if (c.y > 7.0) return vec2(0.0, -1.0);
    // adentro: hacia el lado más cercano
    float l = c.x - 1.0, r = 9.0 - c.x, u = c.y - 1.0, d = 7.0 - c.y;
    float m = min(min(l, r), min(u, d));
    if (m == l) return vec2(-1.0, 0.0);
    if (m == r) return vec2(1.0, 0.0);
    if (m == u) return vec2(0.0, -1.0);
    return vec2(0.0, 1.0);
}

bool isFree(vec2 c) {
    float d = ringDist(c);
    if (d < 0.5) return true;
    float h = hash12(c + seed * 17.0);
    // las esquinas del anillo quedan cerradas: si no, se ve el "afuera" en diagonal
    bool corner = (c.x < 1.0 || c.x > 9.0) && (c.y < 1.0 || c.y > 7.0);
    if (corner) return false;
    if (d < 1.5) return h > 0.55;
    if (d < 2.5) return h > 0.5 && hash12(c + towardRing(c) + seed * 17.0) > 0.55;
    return false;
}

float line(float x, float w) {      // 1 en x=0, cae a 0 a `w` de distancia
    return 1.0 - smoothstep(0.0, w, abs(x));
}

void main() {
    vec2 px = qt_TexCoord0 * res;
    float W = res.x, H = res.y;
    vec2 pos = cam.xy;
    vec2 dir = vec2(cos(cam.z), sin(cam.z));
    vec2 plane = vec2(-dir.y, dir.x) * (0.5 * W / H);
    float camX = 2.0 * px.x / W - 1.0;
    vec2 rd = dir + plane * camX;
    float horizon = H * (0.5 + bob);

    // ---- DDA -------------------------------------------------------------
    vec2 cell = floor(pos);
    vec2 delta = abs(vec2(1.0) / max(abs(rd), vec2(1e-5)));
    vec2 stp = sign(rd);
    vec2 side = (stp * (cell - pos) + stp * 0.5 + 0.5) * delta;
    float hitSide = 0.0;
    float perp = 40.0;
    bool hit = false;
    for (int i = 0; i < 40; i++) {
        if (side.x < side.y) { side.x += delta.x; cell.x += stp.x; hitSide = 0.0; }
        else { side.y += delta.y; cell.y += stp.y; hitSide = 1.0; }
        if (!isFree(cell)) { hit = true; break; }
    }
    if (hit)
        perp = hitSide < 0.5 ? side.x - delta.x : side.y - delta.y;

    float fogA = exp(-perp * fogK * (1.0 - 0.55 * dropAmt));
    vec3 col = bg.rgb;
    float lineHpx = H / max(perp, 1e-3);
    float v = (px.y - horizon) / lineHpx + 0.5;      // 0 arriba .. 1 abajo en la pared

    if (hit && v >= 0.0 && v <= 1.0) {
        float wallX = hitSide < 0.5 ? pos.y + perp * rd.y : pos.x + perp * rd.x;
        wallX = fract(wallX);
        float pxw = perp / H * 1.6;                   // un píxel en unidades de pared
        // ladrillo: 5 hiladas, trabadas
        float row = floor(v * 5.0);
        float bx = fract(wallX * 2.0 + 0.5 * mod(row, 2.0));
        float mortar = max(line(fract(v * 5.0 + 0.5) - 0.5, pxw * 5.0 * 1.2),
                           line(bx - 0.5, pxw * 2.0 * 1.2));
        mortar *= 1.0 - smoothstep(0.0, 1.0, perp / 9.0);
        // aristas: arriba, abajo y el canto donde termina el bloque
        float edge = max(max(line(v, pxw * 4.5), line(v - 1.0, pxw * 4.5)),
                         max(line(wallX, pxw * 4.0), line(wallX - 1.0, pxw * 4.0)));
        // el halo del fósforo alrededor de la arista
        float halo = max(max(line(v, pxw * 18.0), line(v - 1.0, pxw * 18.0)),
                         max(line(wallX, pxw * 14.0), line(wallX - 1.0, pxw * 14.0)));
        float shade = hitSide > 0.5 ? 0.62 : 1.0;
        vec3 face = mix(bg.rgb, ink.rgb, 0.09 * shade);
        // el ladrillo se prende con el golpe en el drop
        col = mix(face, mix(ink.rgb * 0.7, hot.rgb, pulse * dropAmt), mortar * (0.45 + 0.4 * pulse * dropAmt));
        vec3 edgeC = mix(ink.rgb, hot.rgb, 0.35 + 0.65 * pulse);
        col = mix(col, edgeC, halo * halo * (0.4 + 0.3 * pulse));
        col = mix(col, edgeC, edge);
        col += edgeC * halo * halo * 0.18 * (0.5 + pulse);
        col = mix(bg.rgb, col, fogA);
        col += hot.rgb * pulse * 0.08 * fogA;
    } else if (px.y > horizon) {
        // piso: cuadrícula por celda
        float rowDist = H / max(2.0 * (px.y - horizon), 1e-3);
        vec2 fp = pos + rd * rowDist;
        float pxw = rowDist / H * 3.0 * (1.0 + 0.8 * dropAmt);
        vec2 g = abs(fract(fp) - 0.5);
        float grid = max(line(0.5 - g.x, pxw), line(0.5 - g.y, pxw));
        float fa = exp(-rowDist * fogK * (1.0 - 0.55 * dropAmt));
        float gl = (0.55 + 0.4 * dropAmt + 0.4 * pulse * dropAmt) * grid;
        col = mix(bg.rgb, mix(ink.rgb, hot.rgb, pulse * dropAmt), gl * fa);
    } else {
        // techo: puntos fijos, apenas
        float rowDist = H / max(2.0 * (horizon - px.y), 1e-3);
        vec2 fp = pos + rd * rowDist;
        vec2 g = abs(fract(fp) - 0.5);
        float dotv = line(length(0.5 - g), rowDist / H * 3.0);
        float fa = exp(-rowDist * fogK);
        col = mix(bg.rgb, ink.rgb, 0.3 * dotv * fa);
    }
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
