#version 440
// fatal-lyrics — motivo `mystify`: el "Mystify Your Mind" de Windows 95 en fósforo.
//
// Dos (tres con el drop) polígonos de 3..6 vértices que rebotan contra el borde y
// dejan estela. TODO por píxel y analítico: cada eco de la estela es el polígono
// evaluado unos `gap` segundos atrás en el mismo reloj periódico (los vértices son
// ondas triangulares con un número ENTERO de rebotes por loop, así que la figura
// vuelve a su lugar a los 15 s), y el píxel se queda con el eco más cercano a él.
// No hay geometría que reconstruir por cuadro: la CPU sólo manda ~20 números.
//
// Línea = núcleo nítido (antialias analítico) + resplandor que cae exponencial.
// Cada eco es más tenue, más fino y un poco más viejo de color: la estela se
// desvanece en degradé, no en tres escalones.
//
// Build:  /usr/lib/qt6/bin/qsb --glsl '100 es,120,150' -o mystify.frag.qsb mystify.frag
// GLSL 100 es: bucle de cota constante con `break`, sin índices dinámicos de
// uniforms (los vértices van desenrollados).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // vértices por polígono: columna i = (rebotes x, rebotes y, arranque x, arranque y)
    mat4 a0;
    mat4 a1;
    mat4 b0;
    mat4 b1;
    mat4 c0;
    mat4 c1;
    vec4 ink;
    vec4 hot;
    vec2 res;         // píxeles
    float lt;         // reloj del loop (0..15), con la fase integrada de la música
    float gap;        // segundos entre ecos
    float echoes;     // cuántos ecos (≤ 24)
    float nv;         // vértices por polígono (3..6)
    float margin;     // px de borde
    float dropAmt;    // 0..1: el tercer polígono
    float pulse;      // 0..1 el golpe del tiempo
    float high;       // agudos 0..1: color hacia `hot`, resplandor más ancho
    float wpx;        // grosor del núcleo (px)
    float lead0;      // 0..1 cuánto de `hot` lleva cada polígono
    float lead1;
    float lead2;
};

float tri(float u) { return 1.0 - abs(2.0 * fract(u) - 1.0); }

// `t`: segundos hacia atrás desde el frente
vec2 vtx(vec4 q, float t, float k) {
    float u = (lt - t) / 15.0;
    vec2 p = vec2(tri(u * q.x + q.z), tri(u * q.y + q.w));
    p = vec2(margin) + p * (res - vec2(2.0 * margin));
    return mix(res * 0.5, p, k);
}

float seg(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-3), 0.0, 1.0);
    return length(pa - ba * h);
}

// distancia del píxel al polígono `t` segundos atrás (6 aristas; las que
// sobran del `nv` real quedan degeneradas sobre el vértice 0)
float polyDist(vec2 p, mat4 m0, mat4 m1, float t, float k) {
    vec2 v0 = vtx(m0[0], t, k), v1 = vtx(m0[1], t, k), v2 = vtx(m0[2], t, k);
    vec2 v3 = vtx(m0[3], t, k), v4 = vtx(m1[0], t, k), v5 = vtx(m1[1], t, k);
    // el último vértice real cierra contra el 0
    vec2 w3 = nv > 3.5 ? v3 : v0;
    vec2 w4 = nv > 4.5 ? v4 : v0;
    vec2 w5 = nv > 5.5 ? v5 : v0;
    float d = seg(p, v0, v1);
    d = min(d, seg(p, v1, v2));
    d = min(d, seg(p, v2, w3));
    d = min(d, seg(p, w3, w4));
    d = min(d, seg(p, w4, w5));
    d = min(d, seg(p, w5, v0));
    return d;
}

// devuelve (intensidad, edad 0..1 del eco ganador)
vec2 trail(vec2 p, mat4 m0, mat4 m1, float k) {
    float best = 0.0, age = 0.0;
    float glowW = wpx * (3.2 + 2.5 * high + 2.0 * pulse);
    for (int e = 0; e < 24; e++) {
        float fe = float(e);
        if (fe > echoes) break;
        float a = fe / (echoes + 1.0);
        float fade = pow(1.0 - a, 1.7);
        float w = wpx * (1.0 - 0.55 * a);
        float d = polyDist(p, m0, m1, fe * gap, k);
        // núcleo con borde de 1 px + resplandor
        float core = 1.0 - smoothstep(w * 0.5 - 0.5, w * 0.5 + 0.9, d);
        float glow = 0.30 * exp(-d / glowW);
        float i = fade * (core + glow * (1.0 - 0.4 * a));
        if (i > best) { best = i; age = a; }
    }
    return vec2(best, age);
}

vec3 tint(float age, float phase, float lead) {
    // la deriva de color es periódica en el loop (2 y 3 vueltas de seno)
    float s = 0.5 + 0.5 * sin(6.2831853 * (lt / 15.0 * 2.0 - age * 0.35) + phase);
    float toHot = clamp(0.18 + 0.35 * s + 0.45 * lead + 0.3 * high, 0.0, 1.0);
    vec3 c = mix(ink.rgb, hot.rgb, toHot);
    // los ecos viejos se apagan hacia el fósforo puro, sin ir al blanco
    return mix(c, ink.rgb * 0.75, age * 0.6);
}

void main() {
    vec2 p = qt_TexCoord0 * res;
    vec3 rgb = vec3(0.0);
    float alpha = 0.0;

    vec2 r0 = trail(p, a0, a1, 1.0);
    vec3 c0v = tint(r0.y, 0.0, lead0);
    rgb += c0v * r0.x;
    alpha = max(alpha, r0.x);

    vec2 r1 = trail(p, b0, b1, 1.0);
    vec3 c1v = tint(r1.y, 3.1415927, lead1);
    rgb += c1v * r1.x;
    alpha = max(alpha, r1.x);

    if (dropAmt > 0.002) {
        vec2 r2 = trail(p, c0, c1, dropAmt);
        vec3 c2v = tint(r2.y, 1.5707963, lead2);
        rgb += c2v * r2.x * dropAmt;
        alpha = max(alpha, r2.x * dropAmt);
    }
    // el frente de un polígono "caliente" lleva núcleo blanco: sale de `rgb`
    // sumando hot ya en tint; acá sólo se acota para no quemar
    rgb = min(rgb, vec3(1.0));
    alpha = clamp(alpha, 0.0, 1.0);
    // premultiplicado, aditivo sobre la cara
    fragColor = vec4(rgb * qt_Opacity, alpha * qt_Opacity);
}
