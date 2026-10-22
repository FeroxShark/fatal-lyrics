#version 440
// fatal-lyrics — motivo `vitral` (2026-10-22): un vitral de Voronoi, teselas de vidrio con
// plomo oscuro entre ellas. Cada tesela es un cono facetado (la luz le pega de un lado) y los
// centros pasean despacio dentro de su casilla, así que los plomos nunca quedan quietos.
//   · el compás (`bn`, `since`): en cada tiempo se enciende una tanda de teselas (hasta tres
//     tiempos de cola, que se apagan con exp) — la tesela prendida va a `hot`
//   · el bombo (`hitAge`/`hitAmp`/`phys`, el resorte de Thump.js): una onda de choque sale de
//     un punto y EMPUJA los centros hacia afuera con el rebote del resorte; los plomos se
//     doblan y el frente de la onda brilla
//   · agudos (`fizz`): el borde de las teselas titila
//   · densidad (`dens`): se prenden más teselas por tiempo
//   · drop (`dropAmt`): el vidrio se llena de luz
//
// Build:  /usr/lib/qt6/bin/qsb --glsl '100 es,120,150' -o vitral.frag.qsb vitral.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 ink;
    vec4 hot;
    vec4 bg;
    vec4 hitAge;      // s desde cada golpe (el más viejo primero)
    vec4 hitAmp;      // fuerza 0..1
    vec4 hitSeed;     // de dónde sale la onda (0..1)
    vec4 phys;        // (w, wd, zeta·w, 1/rise) del resorte
    vec2 res;
    float physN;      // normalización a pico 1
    float drift;      // fase acumulada, nunca para
    float dens;       // 0..1
    float fizz;       // 0..1
    float bn;         // contador de tiempos
    float since;      // s desde el último tiempo
    float beatS;      // s por tiempo
    float seed;
    float dropAmt;    // 0..1
    float cells;      // teselas por el lado corto
};

float h11(float n) { return fract(sin(n * 12.9898 + 4.1414) * 43758.5453); }
float h21(vec2 p) { return h11(p.x * 57.0 + p.y * 131.0); }

float resp(float age) {
    if (age <= 0.0) return 0.0;
    return (1.0 - exp(-age * phys.w)) * exp(-phys.z * age) * sin(phys.y * age) * physN;
}
float envl(float age) {
    if (age <= 0.0) return 0.0;
    return (1.0 - exp(-age * phys.w)) * exp(-phys.z * age);
}

// cuánto empuja la onda de un golpe a un punto `s` (unidades de tesela), y en qué dirección:
// xy = el empujón, z = la envolvente (para el brillo del frente)
vec3 shock(vec2 s, float age, float amp, float sd) {
    vec2 o = vec2(h11(sd * 91.7), h11(sd * 53.3 + 7.0)) * cells * 1.2 - cells * 0.1;
    vec2 d = s - o;
    float dist = max(length(d), 0.001);
    float a = age - dist / 7.0;
    float k = amp * exp(-dist * 0.07);
    // el frente: una banda que viaja (la cola de la envolvente no ilumina toda la pared)
    float band = exp(-a * a * 28.0) * step(-0.25, a);
    return vec3(d / dist * (0.34 * k * resp(a)), k * band);
}

void main() {
    vec2 uv = (qt_TexCoord0 - 0.5) * res / min(res.x, res.y);
    vec2 p = uv * cells + vec2(41.0, 17.0);
    vec2 g0 = floor(p);

    float f1 = 9.0, f2 = 9.0;
    vec2 s1 = vec2(0.0);
    vec2 id1 = vec2(0.0);
    float front = 0.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 g = g0 + vec2(float(i), float(j));
            float a = h21(g + seed * 13.0), b = h21(g * 1.7 + 3.0 + seed);
            // el centro pasea en una elipse chica dentro de su casilla
            vec2 s = g + 0.5 + 0.34 * vec2(sin(drift * (0.18 + 0.2 * a) + 6.2832 * b),
                                           cos(drift * (0.16 + 0.2 * b) + 6.2832 * a));
            vec2 sp = s - vec2(41.0, 17.0);
            vec3 k0 = shock(sp, hitAge.x, hitAmp.x, hitSeed.x);
            vec3 k1 = shock(sp, hitAge.y, hitAmp.y, hitSeed.y);
            vec3 k2 = shock(sp, hitAge.z, hitAmp.z, hitSeed.z);
            vec3 k3 = shock(sp, hitAge.w, hitAmp.w, hitSeed.w);
            s += k0.xy + k1.xy + k2.xy + k3.xy;
            float dd = length(p - s);
            if (dd < f1) {
                f2 = f1; f1 = dd; s1 = s; id1 = g;
                front = k0.z + k1.z + k2.z + k3.z;
            } else if (dd < f2) {
                f2 = dd;
            }
        }
    }
    front = clamp(front, 0.0, 1.0);

    // la tesela: un cono facetado, con la luz de arriba a la izquierda
    vec2 dir = (p - s1) / max(f1, 0.001);
    float hs = h21(id1 + seed * 7.0);
    float base = 0.06 + 0.30 * hs * hs;
    float facet = 0.5 + 0.5 * dot(dir, normalize(vec2(-0.6, -0.8)));
    float l = base * (0.30 + 1.0 * facet) * (1.0 - 0.5 * f1);

    // las teselas prendidas por el compás: tres tiempos de cola
    float lit = 0.0;
    float thr = 0.07 + 0.10 * dens;
    for (int k = 0; k < 3; k++) {
        float fk = float(k);
        float on = step(h21(id1 + mod(bn - fk, 251.0) * 3.17 + seed * 11.0), thr);
        float age = fk * beatS + since;
        lit = max(lit, on * exp(-age / (beatS * 0.45)));
    }
    l += lit * (0.50 + 0.45 * facet);
    l += dropAmt * 0.12 * (0.3 + hs);
    l += front * 0.35 * (0.4 + facet);

    // el plomo entre teselas (oscuro) con un reborde fino de luz del lado de adentro
    float edge = f2 - f1;
    float lead = smoothstep(0.02, 0.09, edge);
    float rim = (1.0 - smoothstep(0.09, 0.19, edge)) * lead;
    float tw = step(0.9, h21(id1 + floor(drift * 3.0))) * fizz;
    l = l * lead + rim * (0.10 + 0.30 * front + 0.5 * tw + 0.35 * lit);

    vec3 col = mix(bg.rgb, ink.rgb, smoothstep(0.04, 0.62, l));
    col = mix(col, hot.rgb, smoothstep(0.70, 1.10, l));
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
