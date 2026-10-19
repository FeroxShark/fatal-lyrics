#version 440
// fatal-lyrics — motivo `giroscopio` (testeo 2026-10-19): un giróscopo de aros
// anidados (cardán), en 3D de verdad: raymarch de un SDF de 3..6 aros planos, un
// núcleo que late y cuentas que orbitan el aro de afuera. Cada aro gira sobre el eje
// que lo ata al de afuera (X, Y, X, ...): el de adentro hereda todos los giros.
//
// Los ÁNGULOS no se calculan acá: los integra `Giroscopio.qml` (un resorte por aro,
// cada aro con su masa) y llegan hechos. El shader arma las seis matrices UNA vez
// por píxel, fuera del bucle de marcha.
//
// Fondo: polvo de fósforo en tres capas de profundidad que viaja hacia la cámara
// (parallax), así la pantalla nunca queda quieta ni plana.
//
// Build:  /usr/lib/qt6/bin/qsb --glsl '100 es,120,150' -o giroscopio.frag.qsb giroscopio.frag
// GLSL 100 es: bucles de cota constante con `break`, sin derivadas, aros desenrollados.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 ink;
    vec4 hot;
    vec4 bg;
    vec4 angA;        // ángulos de los aros 0..3 (0 = el de afuera)
    vec4 angB;        // (aro 4, aro 5, aros visibles 3..6, cuentas 0..10)
    vec2 res;
    float camD;       // distancia de la cámara (el golpe la acerca)
    float camYaw;
    float camPitch;
    float core;       // 0..1 el latido del núcleo
    float glow;       // 0..1 resplandor del golpe (envolvente)
    float fizz;
    float dens;
    float drift;
    float temper;
};

mat3 M0; mat3 M1; mat3 M2; mat3 M3; mat3 M4; mat3 M5;

mat3 rotX(float a) { float c = cos(a), s = sin(a); return mat3(1.0, 0.0, 0.0, 0.0, c, s, 0.0, -s, c); }
mat3 rotY(float a) { float c = cos(a), s = sin(a); return mat3(c, 0.0, -s, 0.0, 1.0, 0.0, s, 0.0, c); }

const float RAD0 = 1.0;     // radio del aro de afuera
const float STEP = 0.165;   // cuánto achica cada aro hacia adentro

float ringR(float i) { return RAD0 - STEP * i; }
// la visibilidad del aro i (los de adentro entran cuando la canción se llena)
float ringVis(float i) { return clamp(angB.z - i, 0.0, 1.0); }

// un aro plano: sección rectangular redondeada (una banda, como los de un cardán)
float ring(vec3 p, float R, float vis) {
    if (vis <= 0.0) return 1e3;
    vec2 q = vec2(length(p.xy) - R, p.z);
    vec2 b = vec2(0.022, 0.065) * vis;
    vec2 d = abs(q) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - 0.008;
}

// cuentas que orbitan sobre el aro de afuera: repetición angular (UNA esfera evaluada)
float beads(vec3 p) {
    float n = floor(angB.w + 0.5);
    if (n < 1.0) return 1e3;
    float a = atan(p.y, p.x) - drift * 0.9;
    float sec = 6.2831853 / n;
    a = mod(a + 0.5 * sec, sec) - 0.5 * sec;
    float r = length(p.xy);
    vec3 q = vec3(r * cos(a) - (RAD0 + 0.13), r * sin(a), p.z);
    return length(q) - 0.035;
}

// distancia y material (0..5 aro, 6 núcleo, 7 cuentas)
vec2 map(vec3 p) {
    vec3 q0 = M0 * p;
    vec2 d = vec2(ring(q0, ringR(0.0), ringVis(0.0)), 0.0);
    float t;
    t = beads(q0);                                   if (t < d.x) d = vec2(t, 7.0);
    t = ring(M1 * p, ringR(1.0), ringVis(1.0));      if (t < d.x) d = vec2(t, 1.0);
    t = ring(M2 * p, ringR(2.0), ringVis(2.0));      if (t < d.x) d = vec2(t, 2.0);
    t = ring(M3 * p, ringR(3.0), ringVis(3.0));      if (t < d.x) d = vec2(t, 3.0);
    t = ring(M4 * p, ringR(4.0), ringVis(4.0));      if (t < d.x) d = vec2(t, 4.0);
    t = ring(M5 * p, ringR(5.0), ringVis(5.0));      if (t < d.x) d = vec2(t, 5.0);
    t = length(p) - (0.075 + 0.05 * core);           if (t < d.x) d = vec2(t, 6.0);
    return d;
}

vec3 normalAt(vec3 p) {
    const vec2 k = vec2(1.0, -1.0);
    const float e = 0.0015;
    return normalize(k.xyy * map(p + k.xyy * e).x + k.yyx * map(p + k.yyx * e).x
                   + k.yxy * map(p + k.yxy * e).x + k.xxx * map(p + k.xxx * e).x);
}

// el punto en coordenadas del aro `id` (para las marcas que titilan)
vec3 local(vec3 p, float id) {
    if (id < 0.5) return M0 * p;
    if (id < 1.5) return M1 * p;
    if (id < 2.5) return M2 * p;
    if (id < 3.5) return M3 * p;
    if (id < 4.5) return M4 * p;
    return M5 * p;
}

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// polvo de fósforo: tres capas a distinta profundidad que vienen hacia la cámara
vec3 dust(vec2 sp) {
    vec3 acc = vec3(0.0);
    for (int L = 0; L < 3; L++) {
        float fl = float(L);
        // cada capa avanza en z con la deriva; fract la recicla (sin salto: se desvanece en los dos extremos)
        float z = fract(drift * 0.11 + fl / 3.0);
        float sc = mix(9.0, 2.2, z);                 // lejos: celdas chicas; cerca: grandes
        vec2 g = sp * sc + vec2(camYaw * 2.0, camPitch * 2.0) * (0.4 + z) + fl * 17.3;
        vec2 id = floor(g);
        vec2 f = fract(g) - 0.5;
        float h = hash2(id + fl * 31.0);
        if (h > 0.25 + 0.45 * dens) continue;
        vec2 o = vec2(hash2(id + 7.1), hash2(id + 3.3)) - 0.5;
        float r = length(f - 0.7 * o);
        float fade = smoothstep(0.0, 0.25, z) * smoothstep(1.0, 0.75, z);
        float tw = 0.6 + 0.4 * sin(drift * 7.0 + h * 40.0) * fizz;
        acc += ink.rgb * exp(-r * r * 900.0 / (1.0 + 3.0 * z)) * fade * tw * 0.55;
    }
    return acc;
}

void main() {
    vec2 frag = qt_TexCoord0 * res;
    vec2 sp = (frag - 0.5 * res) / res.y;
    sp.y = -sp.y;

    // el cardán: cada aro gira sobre el eje que lo ata al de afuera
    M0 = rotX(angA.x);
    M1 = rotY(angA.y) * M0;
    M2 = rotX(angA.z) * M1;
    M3 = rotY(angA.w) * M2;
    M4 = rotX(angB.x) * M3;
    M5 = rotY(angB.y) * M4;

    // cámara en órbita lenta, mirando al centro
    float cy = cos(camYaw), sy = sin(camYaw), cpi = cos(camPitch), spi = sin(camPitch);
    vec3 ro = camD * vec3(sy * cpi, spi, cy * cpi);
    vec3 fw = normalize(-ro);
    vec3 rt = normalize(cross(vec3(0.0, 1.0, 0.0), fw));
    vec3 up = cross(fw, rt);
    vec3 rd = normalize(fw * 1.55 + rt * sp.x + up * sp.y);

    vec3 col = bg.rgb;
    // resplandor de fondo detrás del giróscopo: respira con la deriva, salta con el golpe
    float rr = length(sp);
    col += ink.rgb * exp(-rr * rr * 3.5) * (0.07 + 0.05 * sin(drift * 0.8) + 0.16 * glow);
    col += dust(sp);

    // esfera envolvente: los rayos que no la tocan no marchan
    float BR = RAD0 + 0.22;
    float b = dot(ro, rd);
    float c = dot(ro, ro) - BR * BR;
    float disc = b * b - c;
    float minD = 1e3;
    if (disc > 0.0) {
        float t = max(-b - sqrt(disc), 0.0);
        float tEnd = -b + sqrt(disc);
        vec2 h = vec2(1e3, -1.0);
        bool hitS = false;
        for (int i = 0; i < 72; i++) {
            vec3 p = ro + rd * t;
            h = map(p);
            minD = min(minD, h.x);
            if (h.x < 0.0012) { hitS = true; break; }
            t += h.x * 0.9;
            if (t > tEnd) break;
        }
        if (hitS) {
            vec3 p = ro + rd * t;
            vec3 n = normalAt(p);
            vec3 v = -rd;
            vec3 l = normalize(vec3(-0.5, 0.8, 0.6));
            float diff = max(dot(n, l), 0.0);
            float spec = pow(max(dot(reflect(-l, n), v), 0.0), mix(14.0, 48.0, temper));
            float fres = pow(1.0 - max(dot(n, v), 0.0), 3.0);
            float id = h.y;
            vec3 base = ink.rgb * (0.10 + 0.62 * diff);
            if (id < 5.5) {
                // marcas a lo largo del aro: con los agudos titilan y corren
                vec3 q = local(p, id);
                float ang = atan(q.y, q.x);
                float tick = smoothstep(0.82, 0.98, cos(ang * 36.0 + drift * (id < 0.5 ? 2.0 : -2.0)));
                base += hot.rgb * tick * (0.10 + 0.9 * fizz) * 0.6;
                // los aros de adentro, un poco más fríos (profundidad del mecanismo)
                base *= 1.0 - 0.06 * id;
            } else if (id < 6.5) {
                base = mix(ink.rgb, hot.rgb, 0.4 + 0.6 * core) * (0.5 + 0.9 * core);
            } else {
                base = mix(ink.rgb, hot.rgb, 0.5) * (0.6 + 0.5 * diff);
            }
            col = base + hot.rgb * (0.85 * spec) + ink.rgb * fres * (0.45 + 0.4 * glow);
        } else {
            // halo de fósforo alrededor de los aros (el rayo pasó cerca)
            col += ink.rgb * exp(-minD * 28.0) * (0.22 + 0.25 * glow);
        }
    }
    col = min(col, vec3(1.0));
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
