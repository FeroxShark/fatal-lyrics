#version 440
// fatal-lyrics — motivo `truchet` (2026-10-22): azulejos de Truchet, dos arcos de cuarto de
// círculo por casilla, que juntos arman un laberinto de cables sin principio ni fin (el
// "10 PRINT" de las placas). Cada casilla gira un cuarto de vuelta de tanto en tanto, y al
// girar se ve el arco barrer la casilla como un engranaje.
//   · el compás (`bn`, `since`, `beatS`): cada casilla tiene su período (1, 2, 4 u 8 tiempos,
//     con su fase) y gira SIEMPRE en un tiempo, con el snap de Motion (OutExpo 320 ms): en
//     cada tiempo giran las de período 1 y una parte de las demás
//   · el bombo (`hitAge`/`hitAmp`/`phys`, el resorte de Thump.js): una onda sale de un punto
//     y viaja por la red; donde pasa, los cables engordan y los empalmes se encienden
//   · agudos (`fizz`): los empalmes de los bordes de casilla titilan
//   · densidad (`dens`): giran más casillas por tiempo
//   · drop (`dropAmt`): los cables frescos se ponen al rojo
// La red se desliza sola (`drift`) aunque no suene nada.
// PARED (`docs/PARED.md`): `view` es la ventana de esta pantalla en el lienzo común (en
// unidades del lado corto, desde el centro del lienzo); con `wallK` las ondas salen del foco
// (la pantalla de la letra, o el medio del lienzo) y cruzan la pared.
//
// Build:  /usr/lib/qt6/bin/qsb --glsl '100 es,120,150' -o truchet.frag.qsb truchet.frag

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
    float physN;      // normalización a pico 1
    float drift;      // fase acumulada, nunca para
    float dens;       // 0..1
    float fizz;       // 0..1
    float bn;         // contador de tiempos
    float since;      // s desde el último tiempo
    float beatS;      // s por tiempo
    float seed;
    float dropAmt;    // 0..1
    float cells;      // casillas por el lado corto
    vec4 view;        // uv = view.xy + qt_TexCoord0 · view.zw (sin pared: la pantalla centrada)
    vec2 foc;         // de dónde salen las ondas en pared (mismas unidades que `uv`)
    float wallK;      // 1 = pared
};

float h11(float n) { return fract(sin(n * 12.9898 + 4.1414) * 43758.5453); }
float h21(vec2 p) { return h11(p.x * 57.0 + p.y * 131.0); }
float outExpo(float x) { return x >= 1.0 ? 1.0 : 1.0 - exp2(-10.0 * x); }

float envl(float age) {
    if (age <= 0.0) return 0.0;
    return (1.0 - exp(-age * phys.w)) * exp(-phys.z * age);
}
// la onda del golpe en el punto `p` (unidades de casilla): viaja a ~6 casillas por s
float wave(vec2 p, float age, float amp, float sd) {
    vec2 h = vec2(h11(sd * 91.7), h11(sd * 53.3 + 7.0));
    // pared: cerca del foco (con la red, que se desliza), así la onda cruza las pantallas
    vec2 o = wallK > 0.5 ? foc * cells + vec2(drift * 0.11, drift * 0.07) + (h - 0.5) * cells * 0.8
                         : h * cells * 1.1 - cells * 0.1;
    float d = length(p - o);
    float a = age - d / 6.5;
    float band = exp(-a * a * 20.0) * step(-0.3, a);
    return amp * (band + 0.22 * envl(a)) * exp(-d * 0.045);
}

void main() {
    vec2 uv = view.xy + qt_TexCoord0 * view.zw;
    vec2 p = uv * cells + vec2(drift * 0.11, drift * 0.07) + vec2(37.0, 11.0);
    vec2 id = floor(p);
    vec2 f = fract(p) - 0.5;

    // el golpe: una onda por bombo, que viaja por la red
    vec2 pc = p - vec2(37.0, 11.0);
    float wv = wave(pc, hitAge.x, hitAmp.x, hitSeed.x) + wave(pc, hitAge.y, hitAmp.y, hitSeed.y)
             + wave(pc, hitAge.z, hitAmp.z, hitSeed.z) + wave(pc, hitAge.w, hitAmp.w, hitSeed.w);
    wv = clamp(wv, 0.0, 1.0);

    // el período de la casilla (1, 2, 4 u 8 tiempos) y su fase
    float hp = h21(id + seed * 17.0);
    float hq = h21(id * 1.37 + 5.0 + seed * 3.0);
    float act = hp - 0.18 * dens;                  // la densidad mueve el reparto hacia los períodos cortos
    float P = act < 0.22 ? 1.0 : (act < 0.50 ? 2.0 : (act < 0.80 ? 4.0 : 8.0));
    float off = floor(hq * P);
    float cnt = bn + off;
    float kf = floor(cnt / P);
    float age = (cnt - kf * P) * beatS + since;     // s desde el último giro
    float turn = outExpo(clamp(age / 0.32, 0.0, 1.0));
    float o0 = floor(h21(id + 9.0 + seed * 5.0) * 2.0);
    float ang = (mod(kf, 4.0) - 1.0 + turn + o0) * 1.5707963;     // sólo importa mod 4 (y `kf` llega en miles)
    float ca = cos(ang), sa = sin(ang);
    vec2 q = vec2(f.x * ca + f.y * sa, -f.x * sa + f.y * ca);

    // los dos arcos, centrados en esquinas opuestas
    float d1 = abs(length(q - vec2(-0.5, -0.5)) - 0.5);
    float d2 = abs(length(q - vec2(0.5, 0.5)) - 0.5);
    float d = min(d1, d2);
    float inBox = step(max(abs(q.x), abs(q.y)), 0.5);

    float w = 0.055 + 0.05 * wv;                    // el cable engorda donde pasa la onda
    float core = (1.0 - smoothstep(w * 0.55, w, d)) * inBox;
    float halo = exp(-d * 11.0) * inBox * 0.30;
    float rail = (1.0 - smoothstep(0.0, w * 0.55, abs(d - 0.17) )) * inBox * 0.36;   // el segundo cable, más flaco
    float fresh = 1.0 - smoothstep(0.0, 0.85, age / beatS);

    float l = 0.05 + halo * (0.8 + 1.2 * wv) + rail * 0.9 + core * (0.62 + 0.55 * fresh * (0.5 + 0.7 * dropAmt) + 0.5 * wv);

    // empalmes: el medio de cada borde de casilla, donde los arcos se tocan
    vec2 fe = abs(f);
    float de = min(length(fe - vec2(0.5, 0.0)), length(fe - vec2(0.0, 0.5)));
    float tw = step(0.8, h21(id + floor(drift * 2.5))) * fizz;
    l += (1.0 - smoothstep(0.045, 0.085 + 0.04 * wv, de)) * (0.55 + 0.6 * wv + 0.6 * tw);

    vec3 col = mix(bg.rgb, ink.rgb, smoothstep(0.05, 0.62, l));
    col = mix(col, hot.rgb, smoothstep(0.78, 1.15, l));
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
