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
// Los huevos de pascua (Maze.qml decide cuál y cuándo; acá sólo se dibujan, todo por
// código, ningún asset): carita, diálogo de error de Win95 y cartel SALIDA en una
// pared del fondo del tramo; rata y poliedro como sprites que miran a la cámara.
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
    float roll;       // rad: el mundo da vuelta (0 = derecho, pi = patas arriba)
    vec4 egg;         // huevo de pascua: celda x, y, tipo (0 nada, 1 carita, 2 diálogo,
                      // 3 salida, 4 rata, 5 poliedro), edad en s
    vec4 eggB;        // rumbo del cartel (x, y), cuánto se ve (0..1)
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
    // la pared del cartel se cierra aunque ahí hubiera un nicho
    if (egg.z > 0.5 && egg.z < 3.5 && abs(c.x - egg.x) < 0.5 && abs(c.y - egg.y) < 0.5)
        return false;
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

// ---- decorados. p en unidades de pared, (0.5, 0.5) = el centro, v hacia abajo.
float disc(vec2 p, vec2 c, float r, float w) { return 1.0 - smoothstep(r - w, r + w, length(p - c)); }
float sdBox(vec2 p, vec2 c, vec2 h) {
    vec2 q = abs(p - c) - h;
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
}
float fillBox(vec2 p, vec2 c, vec2 h, float w) { return 1.0 - smoothstep(-w, w, sdBox(p, c, h)); }
float edgeBox(vec2 p, vec2 c, vec2 h, float w) { return line(sdBox(p, c, h), w); }
// glifo 3x5 (15 bits, fila a fila; bit 0 = arriba a la izquierda)
float glyph(float code, vec2 g) {
    float bit = floor(g.y) * 3.0 + floor(g.x);
    return mod(floor(code / exp2(bit) + 1e-3), 2.0);
}
float letter(int i, vec2 g) {
    float code = 31183.0;                       // S
    if (i == 1 || i == 5) code = 23530.0;       // A
    else if (i == 2) code = 29257.0;            // L
    else if (i == 3) code = 29847.0;            // I
    else if (i == 4) code = 15211.0;            // D
    return glyph(code, g);
}

// (relleno, trazo) del decorado `kind` en la cara de la pared
vec2 decal(float kind, vec2 uv, float w) {
    vec2 p = uv;
    float fillM = 0.0, strokeM = 0.0;
    if (kind < 1.5) {                                    // carita
        vec2 q = p - 0.5;
        fillM = disc(p, vec2(0.5), 0.30, w) * 0.5;
        strokeM = line(length(q) - 0.30, w * 3.0);
        strokeM = max(strokeM, disc(p, vec2(0.39, 0.42), 0.055, w));
        strokeM = max(strokeM, disc(p, vec2(0.61, 0.42), 0.055, w));
        strokeM = max(strokeM, line(length(p - vec2(0.5, 0.46)) - 0.19, w * 3.0) * step(0.53, p.y));
    } else if (kind < 2.5) {                             // diálogo de error
        fillM = fillBox(p, vec2(0.5, 0.5), vec2(0.38, 0.30), w) * 0.5;
        fillM = max(fillM, fillBox(p, vec2(0.5, 0.25), vec2(0.38, 0.05), w));
        strokeM = edgeBox(p, vec2(0.5, 0.5), vec2(0.38, 0.30), w * 2.5);
        strokeM = max(strokeM, edgeBox(p, vec2(0.79, 0.25), vec2(0.045, 0.035), w * 2.0));
        strokeM = max(strokeM, edgeBox(p, vec2(0.5, 0.71), vec2(0.10, 0.045), w * 2.0));
        vec2 ic = p - vec2(0.27, 0.5);
        strokeM = max(strokeM, line(length(ic) - 0.075, w * 2.5));
        float cross = max(line(ic.x - ic.y, w * 2.5), line(ic.x + ic.y, w * 2.5)) * step(length(ic), 0.05);
        strokeM = max(strokeM, cross);
        strokeM = max(strokeM, fillBox(p, vec2(0.62, 0.46), vec2(0.17, 0.012), w));
        strokeM = max(strokeM, fillBox(p, vec2(0.58, 0.54), vec2(0.13, 0.012), w));
    } else {                                             // SALIDA
        fillM = fillBox(p, vec2(0.5, 0.30), vec2(0.42, 0.13), w) * 0.55;
        fillM = max(fillM, fillBox(p, vec2(0.5, 0.78), vec2(0.20, 0.17), w) * 0.3);
        strokeM = edgeBox(p, vec2(0.5, 0.30), vec2(0.42, 0.13), w * 2.5);
        strokeM = max(strokeM, edgeBox(p, vec2(0.5, 0.78), vec2(0.20, 0.17), w * 2.5));
        float c = 0.033;
        vec2 g = (p - vec2(0.5 - 11.5 * c, 0.30 - 2.5 * c)) / c;
        float idx = floor(g.x / 4.0);
        float inx = g.x - 4.0 * idx;
        if (idx >= 0.0 && idx < 6.0 && inx < 3.0 && g.y >= 0.0 && g.y < 5.0)
            strokeM = max(strokeM, letter(int(idx), vec2(inx, g.y)));
    }
    return vec2(fillM, strokeM);
}

// la rata: a ras del piso, cruzando el pasillo de una pared a la otra
float ratShape(vec2 p, float age) {
    float w = 0.006;
    vec2 r = vec2(0.13, 0.06);
    float body = 1.0 - smoothstep(-w, w, (length((p - vec2(0.0, 0.075)) / r) - 1.0) * 0.06);
    vec2 hr = vec2(0.075, 0.045);
    float head = 1.0 - smoothstep(-w, w, (length((p - vec2(0.15, 0.085)) / hr) - 1.0) * 0.045);
    float ear = disc(p, vec2(0.13, 0.135), 0.022, w);
    float tailY = 0.06 + 0.03 * sin(age * 28.0 - p.x * 30.0);
    float tail = (1.0 - smoothstep(0.0, 0.01, abs(p.y - (0.07 + (tailY - 0.07) * (-p.x - 0.1) * 5.0))))
                 * step(-0.34, p.x) * step(p.x, -0.11);
    float leg = (1.0 - smoothstep(0.0, 0.012, abs(p.x - 0.07 * sin(age * 40.0)))) * step(p.y, 0.03) * step(-0.02, p.y);
    return max(max(max(body, head), max(ear, tail)), leg);
}

// el poliedro: un octaedro que gira; (relleno, aristas)
vec2 rockShape(vec2 p, float age) {
    vec2 c = vec2(0.0, 0.24 + 0.02 * sin(age * 3.0));
    vec2 q = p - c;
    float w = 0.008;
    float diamond = abs(q.x) / 0.17 + abs(q.y) / 0.22;
    float fillM = (1.0 - smoothstep(0.98, 1.0 + w * 6.0, diamond));
    float rot = age * 1.7;
    float e1 = 0.17 * sin(rot), e2 = 0.17 * sin(rot + 1.5708);
    float edges = line(diamond - 1.0, 0.05);
    float inside = 1.0 - smoothstep(0.96, 1.0, diamond);
    edges = max(edges, line(q.x - e1, w * 1.5) * inside);
    edges = max(edges, line(q.x - e2, w * 1.5) * inside);
    edges = max(edges, line(q.y, w * 1.5) * inside * 0.7);
    float shade = 0.5 + 0.5 * cos(rot + q.x * 9.0);
    return vec2(fillM * (0.25 + 0.35 * shade), edges);
}

void main() {
    vec2 px = qt_TexCoord0 * res;
    float W = res.x, H = res.y;
    // el mundo da vuelta: se rota la pantalla entera alrededor del centro
    if (abs(roll) > 1e-4) {
        vec2 d0 = px - 0.5 * res;
        float cr = cos(roll), sr = sin(roll);
        px = 0.5 * res + vec2(cr * d0.x - sr * d0.y, sr * d0.x + cr * d0.y);
    }
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
        if (egg.z > 0.5 && egg.z < 3.5 && abs(cell.x - egg.x) < 0.5 && abs(cell.y - egg.y) < 0.5) {
            vec2 fn = hitSide < 0.5 ? vec2(stp.x, 0.0) : vec2(0.0, stp.y);
            if (dot(fn, eggB.xy) > 0.5) {
                float uu = hitSide < 0.5 ? (stp.x > 0.0 ? wallX : 1.0 - wallX)
                                         : (stp.y > 0.0 ? 1.0 - wallX : wallX);
                vec2 dm = decal(egg.z, vec2(uu, v), pxw * 1.5);
                vec3 hi = mix(ink.rgb, hot.rgb, 0.55 + 0.45 * pulse);
                col = mix(col, mix(bg.rgb, ink.rgb, 0.45), dm.x * eggB.z);
                col = mix(col, hi, dm.y * eggB.z);
            }
        }
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
    // ---- sprites: rata y poliedro, planos que miran a la cámara ---------------
    if (egg.z > 3.5) {
        vec2 sp = egg.xy + 0.5;
        float age = egg.w;
        float hs = 1.0;
        if (egg.z < 4.5) {                                // la rata cruza de lado a lado
            vec2 sideV = vec2(eggB.y, -eggB.x);
            float u = clamp(age / 1.1, 0.0, 1.0);
            sp += sideV * (mix(-0.7, 0.7, u) + 0.03 * sin(age * 21.0));
            hs = dot(sideV, plane) >= 0.0 ? 1.0 : -1.0;
        }
        vec2 rel = sp - pos;
        float D = dir.x * plane.y - plane.x * dir.y;
        float ty = (plane.y * rel.x - plane.x * rel.y) / D;
        float txn = (-dir.y * rel.x + dir.x * rel.y) / D;
        if (ty > 0.2 && ty < perp) {
            float camXs = txn / ty;
            float lx = (camX - camXs) * ty * (0.5 * W / H);
            float ly = 0.5 - (px.y - horizon) * ty / H;
            float sfog = exp(-ty * fogK * (1.0 - 0.55 * dropAmt));
            vec3 hi = mix(ink.rgb, hot.rgb, 0.6 + 0.4 * pulse);
            if (egg.z < 4.5) {
                float u = clamp(age / 1.1, 0.0, 1.0);
                float a = smoothstep(0.0, 0.12, u) * (1.0 - smoothstep(0.85, 1.0, u));
                float r = ratShape(vec2(lx * hs, ly) / 1.25, age);
                col = mix(col, hi, r * a * sfog);
            } else {
                vec2 rk = rockShape(vec2(lx, ly), age);
                col = mix(col, mix(bg.rgb, ink.rgb, 0.7), rk.x * eggB.z * sfog);
                col = mix(col, hi, rk.y * eggB.z * sfog);
            }
        }
    }
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
