#version 440
// fatal-lyrics — motivo `rain`: lluvia de caracteres de verdad, tres planos de profundidad.
//   · cada columna tiene su velocidad, su largo y su cabeza; la cabeza baja de a una casilla, como
//     un terminal que escribe, y deja una cola que se apaga
//   · los caracteres cambian solos, y más rápido con los agudos (`fizz`)
//   · bombo (`hitAge`/`hitAmp`): un frente caliente baja por las columnas que le tocan a ese golpe
//   · densidad (`dens`): más columnas despiertas y colas más largas
// La caída sale de `drift`, acumulada: nunca `reloj × velocidad`, y nada que cambie multiplica a
// la caída (el drop la haría saltar entera).
// PARED (`docs/PARED.md`): `view` es la ventana de esta pantalla en el lienzo; las columnas siguen
// de una pantalla a la otra. `topU` es el techo del lienzo: de ahí salen los frentes del bombo.
//
// Costo: UN ShaderEffect, tres búsquedas de textura por píxel (más hasta tres, sin bucles anidados).
// Build:  /usr/lib/qt6/bin/qsb --glsl '100 es,120,150' -o rain.frag.qsb rain.frag

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
    vec4 hitSeed;
    vec4 view;      // uv = view.xy + qt_TexCoord0 · view.zw, en unidades del lado corto
    float drift;
    float dens;
    float fizz;
    float dropAmt;
    float seed;
    float topU;
};
layout(binding = 1) uniform sampler2D atlas;   // 16 × 4 caracteres (`Rain.qml`)

float h11(float n) { return fract(sin(n * 12.9898 + 4.1414) * 43758.5453); }
float h21(float a, float b) { return h11(a * 57.31 + b * 131.17); }

// el caracter `g` (0..63) en la casilla, `l` 0..1
float glyph(float g, vec2 l) {
    float cx = mod(g, 16.0), cy = floor(g / 16.0);
    // adentrito de la celda: el borde de la de al lado no se cuela
    vec2 q = 0.04 + 0.92 * l;
    return texture(atlas, (vec2(cx, cy) + q) / vec2(16.0, 4.0)).r;
}

float front(float age, float amp, float sd, float id, float row) {
    if (amp <= 0.0 || age > 3.0) return 0.0;
    if (h21(id, floor(sd * 997.0)) > 0.18 + 0.32 * amp) return 0.0;
    float d = age * 34.0 - row;   // casillas detrás del frente
    if (d < 0.0 || d > 14.0) return 0.0;
    return exp(-d * 0.28) * min(amp * 1.4, 1.0);
}

vec3 plane(vec2 uv, float z, float pl, float top) {
    float cs = mix(0.0165, 0.040, z);            // alto de la casilla
    float cw = cs * 0.74;
    vec2 g = vec2(uv.x / cw, uv.y / cs);
    float id = floor(g.x), cy = floor(g.y);
    vec2 l = fract(g);
    float k = id + pl * 311.0 + seed * 71.0;

    // columnas: las cercanas están más separadas, si no la letra de adelante tapa todo
    float awake = mix(0.62, 0.40, z) + 0.34 * dens + 0.14 * dropAmt;
    bool live = h11(k * 1.37) < awake;

    float speed = mix(5.0, 11.0, z) * (0.65 + 0.7 * h11(k * 2.11));
    float period = 30.0 + floor(26.0 * h11(k * 3.7));
    float head = floor(drift * speed + period * h11(k * 5.3));
    float d = mod(head - cy, period);
    float len = (7.0 + 15.0 * h11(k * 7.1)) * (0.6 + 0.7 * dens);

    float row = cy - top / cs;
    float kickF = z < 0.25 ? 0.0
        : front(hitAge.x, hitAmp.x, hitSeed.x, k, row) + front(hitAge.y, hitAmp.y, hitSeed.y, k, row)
        + front(hitAge.z, hitAmp.z, hitSeed.z, k, row) + front(hitAge.w, hitAmp.w, hitSeed.w, k, row);

    float tail = (live && d < len) ? pow(1.0 - d / len, 1.6) : 0.0;
    if (tail <= 0.0 && kickF <= 0.0) return vec3(0.0);

    // cada casilla cambia a su ritmo; con agudos, más
    float rate = (0.5 + 2.6 * h21(k, cy)) * (1.0 + 2.5 * fizz);
    float gid = floor(64.0 * h21(k + 0.5, cy + floor(drift * rate + 9.0 * h21(cy, k))));
    if (h21(k * 0.7, gid) > 0.5) l.x = 1.0 - l.x;
    float a = glyph(gid, l);

    float isHead = (live && d < 1.0) ? 1.0 : 0.0;
    float gain = mix(0.30, 1.0, z);
    vec3 c = ink.rgb * (0.08 + 0.92 * tail) * tail * gain
           + hot.rgb * isHead * mix(0.45, 1.1, z)
           + mix(ink.rgb, hot.rgb, 0.65) * kickF * gain;
    return c * a;
}

void main() {
    vec2 uv = view.xy + qt_TexCoord0 * view.zw;
    vec3 col = bg.rgb;
    col += plane(uv, 0.0, 0.0, topU);
    col += plane(uv + vec2(0.0043, 0.0), 0.5, 1.0, topU);
    col += plane(uv + vec2(0.0117, 0.0), 1.0, 2.0, topU);
    fragColor = vec4(min(col, vec3(1.0)), 1.0) * qt_Opacity;
}
