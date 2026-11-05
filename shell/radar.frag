#version 440
// fatal-lyrics — motivo `radar`: una pantalla de radar (PPI) de verdad.
//   · el barrido gira y el fósforo se apaga detrás: lo que se ve es lo que la aguja acaba de tocar
//   · la costa sale de ruido en coordenadas polares discretas: retornos en bloques, como un radar
//   · contactos (`c0..c2`) con su estela de retornos viejos; se prenden cuando la aguja les pasa
//   · bombo (`hitAge`/`hitAmp`): un pulso sale del centro y aclara la costa a su paso
//   · agudos (`fizz`): el ruido del mar cerca del centro
//   · drop (`dropAmt`): el fósforo se va al color caliente
//
// Costo: UN ShaderEffect, cuatro octavas de ruido por píxel adentro del disco.
// Build:  /usr/lib/qt6/bin/qsb --glsl '100 es,120,150' -o radar.frag.qsb radar.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 ink;
    vec4 hot;
    vec4 bg;
    vec4 hitAge;
    vec4 hitAmp;
    vec4 c0, c1, c2;   // contactos, de a dos por vec4, en radios del disco
    vec4 v0, v1, v2;   // su velocidad, igual
    vec2 res;
    float sweep;       // ángulo de la aguja (rad)
    float dens;
    float fizz;
    float dropAmt;
    float seed;
    float flash;       // 0..1 el golpe
};

const float TAU = 6.2831853;
const float RAD = 0.455;      // radio del disco, en lados cortos

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x),
               mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
    float a = 0.5, s = 0.0;
    for (int i = 0; i < 4; i++) {
        s += a * noise(p);
        p = p * 2.03 + vec2(17.3, 9.1);
        a *= 0.5;
    }
    return s / 0.9375;
}

// cuánto hace (rad) que la aguja pasó por el ángulo `a`
float since(float a) { return mod(sweep - a, TAU); }

vec3 contact(vec2 p, vec2 c, vec2 v, float px, float lock) {
    float a = atan(c.y, c.x);
    float lit = exp(-since(a) * 0.62);
    vec2 q = p - c;
    float d = length(q);
    float s = 0.012 + 0.012 * lit;
    float blip = exp(-d * d / (s * s));
    // la estela: cuatro retornos viejos, cada vez más tenues
    float tail = 0.0;
    for (int i = 1; i <= 4; i++) {
        float fi = float(i);
        vec2 o = c - v * fi * 1.5;
        vec2 w = p - o;
        tail += exp(-dot(w, w) / (0.0065 * 0.0065)) * (1.0 - fi / 5.0);
    }
    // el recuadro del contacto seguido
    vec2 aq = abs(q);
    float box = 0.042 + 0.006 * flash;
    float edge = abs(max(aq.x, aq.y) - box);
    float corner = step(box * 0.45, min(aq.x, aq.y));
    float frame = lock * smoothstep(1.6 * px, 0.6 * px, edge) * corner;
    return hot.rgb * blip * (0.14 + 1.25 * lit) + ink.rgb * tail * (0.10 + 0.55 * lit)
         + hot.rgb * frame * 0.75;
}

void main() {
    vec2 frag = qt_TexCoord0 * res;
    float side = min(res.x, res.y);
    vec2 uv = (frag - 0.5 * res) / side;
    vec2 p = uv / RAD;
    float px = 1.0 / (side * RAD);
    float r = length(p);
    float th = atan(p.y, p.x);
    if (th < 0.0) th += TAU;

    vec3 col = bg.rgb;

    // afuera: una grilla de puntos de consola, apenas
    vec2 g = abs(fract(uv / 0.05 + 0.5) - 0.5) * 0.05 * side;
    float dots = exp(-dot(g, g) / 1.6);
    float outside = smoothstep(1.07, 1.09, r);
    col += ink.rgb * 0.13 * dots * outside;

    if (r < 1.09) {
        float inside = smoothstep(1.0 + px, 1.0 - px, r);
        float age = since(th);
        // fósforo: lo recién tocado brilla, y sigue el resto de la vuelta casi apagado
        float phos = exp(-age * 0.95);

        // el fondo del disco, un poco más claro que la cara
        col += ink.rgb * (0.025 + 0.05 * (1.0 - r)) * inside;

        // retornos en bloques polares
        float bins = 150.0;
        float ang = floor(th / TAU * 420.0 + 0.5) / 420.0 * TAU;
        float rq = floor(r * bins + 0.5) / bins;
        vec2 pq = rq * vec2(cos(ang), sin(ang));
        vec2 off = vec2(seed * 41.0, seed * 73.0);
        float n = fbm(pq * 2.25 + off);
        // el centro queda en el agua: ahí está el barco que mira
        float landing = smoothstep(0.20, 0.42, r);
        float land = smoothstep(0.545, 0.565, n) * landing;
        float inner = smoothstep(0.60, 0.70, n) * landing;
        float coast = land * (1.0 - smoothstep(0.565, 0.59, n));

        // el pulso del bombo: un anillo que sale del centro y aclara lo que toca
        float ping = 0.0;
        for (int i = 0; i < 4; i++) {
            float a = i == 0 ? hitAge.x : i == 1 ? hitAge.y : i == 2 ? hitAge.z : hitAge.w;
            float m = i == 0 ? hitAmp.x : i == 1 ? hitAmp.y : i == 2 ? hitAmp.z : hitAmp.w;
            if (m > 0.0 && a < 1.4) {
                float d = r - a * 1.25;
                ping += min(m, 1.0) * exp(-d * d / 0.0028) * exp(-a * 2.1);
            }
        }

        vec3 ph = mix(ink.rgb, hot.rgb, 0.25 + 0.55 * dropAmt);
        float seen = 0.07 + 0.95 * phos;
        col += ink.rgb * land * (0.30 + 0.25 * inner) * seen * inside;
        col += ph * coast * (0.25 + 1.0 * phos) * inside;
        col += ph * land * ping * 0.9 * inside;

        // el mar cerca del centro: retorno que titila, más con agudos
        float sea = h21(vec2(ang * 37.0, rq * 91.0) + floor(sweep * 2.0));
        float seaAmt = (1.0 - smoothstep(0.05, 0.42, r)) * (0.28 + 0.5 * fizz + 0.2 * dens);
        col += ink.rgb * step(0.80, sea) * seaAmt * (0.06 + 0.8 * phos) * inside;

        // la grilla: anillos de distancia, cruz y marcas de rumbo
        float rings = 0.0;
        for (int i = 1; i <= 3; i++) {
            float d = abs(r - float(i) * 0.25);
            rings = max(rings, smoothstep(1.5 * px, 0.4 * px, d));
        }
        // cada anillo con su punteado, cada 10°
        float dash = step(0.38, fract(th / TAU * 72.0));
        float cross = max(smoothstep(1.3 * px, 0.3 * px, abs(p.x)), smoothstep(1.3 * px, 0.3 * px, abs(p.y)));
        col += ink.rgb * (rings * dash * 0.30 + cross * 0.17) * inside;

        // el aro y sus marcas: cada 10°, y cada 30° más largas
        float rim = smoothstep(2.2 * px, 0.6 * px, abs(r - 1.0));
        col += mix(ink.rgb, hot.rgb, 0.25) * rim * 0.85;
        float t10 = abs(fract(th / TAU * 36.0 + 0.5) - 0.5) / 36.0 * TAU * r;
        float t30 = abs(fract(th / TAU * 12.0 + 0.5) - 0.5) / 12.0 * TAU * r;
        float tick10 = smoothstep(1.4 * px, 0.4 * px, t10) * step(1.0, r) * step(r, 1.022);
        float tick30 = smoothstep(1.8 * px, 0.6 * px, t30) * step(1.0, r) * step(r, 1.05);
        col += ink.rgb * max(tick10 * 0.7, tick30);

        // la aguja: línea caliente y un resplandor corto detrás
        float d2 = r * sin(min(age, 1.5));
        float needle = age < 1.2 ? smoothstep(2.4 * px, 0.5 * px, abs(d2)) : 0.0;
        if (TAU - age < 0.02) needle = max(needle, smoothstep(2.4 * px, 0.5 * px, r * sin(TAU - age)));
        col += ph * needle * inside * 1.25;
        col += ink.rgb * exp(-age * 7.0) * 0.20 * inside;

        // el pulso se ve también en el agua, tenue
        col += ink.rgb * ping * 0.22 * inside;

        // contactos
        vec3 cc = contact(p, c0.xy, v0.xy, px, 1.0)
                + contact(p, c0.zw, v0.zw, px, 0.0)
                + contact(p, c1.xy, v1.xy, px, 0.0)
                + contact(p, c1.zw, v1.zw, px, 0.0)
                + contact(p, c2.xy, v2.xy, px, 0.0)
                + contact(p, c2.zw, v2.zw, px, 0.0);
        col += cc * inside;

        // el centro: el que mira
        float own = exp(-r * r / 0.0002);
        col += hot.rgb * own * 0.9;
    }

    fragColor = vec4(min(col, vec3(1.0)), 1.0) * qt_Opacity;
}
