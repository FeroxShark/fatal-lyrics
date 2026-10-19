#version 440
// fatal-lyrics — motivo `cintas` (testeo 2026-10-19): cintas de fósforo tendidas a
// distintas profundidades, como cuerdas de un bajo vistas de costado. Cada golpe
// del bombo las PULSA: la cinta se comba (modo 1), suma un poco del modo 2, y se
// retuerce sobre su eje; las de atrás pesan más, responden más tarde y más lento
// (overlap y follow-through: la ola baja por la pila de adelante hacia atrás).
//
// Todo analítico por píxel: ≤ 8 capas, 4 golpes desenrollados. Se compone de atrás
// hacia adelante: el relleno de una cinta cercana tapa a las de atrás.
//
// Build:  /usr/lib/qt6/bin/qsb --glsl '100 es,120,150' -o cintas.frag.qsb cintas.frag

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
    vec4 phys;        // (w, wd, zeta·w, 1/rise)
    vec2 res;
    float physN;
    float drift;
    float dens;
    float fizz;
    float temper;
    float camX;
    float camY;
    float layers;     // capas visibles (3..8, con fracción: la que entra, entra de a poco)
    float bend;       // cuánto se comba con un golpe (unidades de mundo)
    float twist;      // vueltas de la cinta por unidad
    float seed;
};

// la masa `k` (1 = adelante): más pesada, más lenta; el ataque se ablanda igual
float resp(float age, float k) {
    if (age <= 0.0) return 0.0;
    float sk = inversesqrt(k);
    return (1.0 - exp(-age * phys.w * sk)) * exp(-phys.z * sk * age) * sin(phys.y * sk * age) * physN;
}

float h1(float n) { return fract(sin(n * 127.1 + seed * 311.7) * 43758.5453); }

// combadura de la capa en `u` (0..1 de punta a punta) por un golpe
float pluck(float u, float age, float amp, float sd, float k, float delay) {
    if (amp <= 0.0 || age > 8.0) return 0.0;
    float u0 = 0.25 + 0.5 * sd;                       // dónde la pulsa
    float a = age - delay - 0.18 * sqrt((u - u0) * (u - u0) + 0.004);        // la ola sale del punto pulsado
    float sgn = fract(sd * 5.3) > 0.5 ? 1.0 : -1.0;
    return amp * sgn * (sin(3.1415927 * u) * resp(a, k)
                        + 0.35 * sin(6.2831853 * u + sd * 6.0) * resp(a * 1.6, k));
}

void main() {
    vec2 frag = qt_TexCoord0 * res;
    vec2 sp = (frag - 0.5 * res) / res.y;
    sp.y = -sp.y;
    float aspect = res.x / res.y;
    float pxw = 1.0 / res.y;

    vec3 col = bg.rgb;
    float n = clamp(layers, 1.0, 8.0);

    for (int j = 0; j < 8; j++) {
        // de atrás hacia adelante
        float l = 7.0 - float(j);
        float vis = clamp(n - l, 0.0, 1.0);
        if (vis <= 0.0) continue;
        float z = 1.0 + l * 0.42;
        float s = 1.0 / z;
        float fog = exp(-l * 0.22);
        float k = 1.0 + 0.55 * l;                       // masa
        float delay = 0.045 * l;                        // la ola baja por la pila
        float xw = sp.x / s + camX;
        float E = (aspect * 0.5 + 0.25) / s;            // las puntas, justo afuera de cuadro
        float u = clamp((xw + E) / (2.0 * E), 0.0, 1.0);
        float y0 = ((fract(l * 0.618 + 0.31) - 0.5) * 0.75 + (h1(l) - 0.5) * 0.12) / s;
        float tilt = (h1(l + 9.0) - 0.5) * 0.25;
        // la deriva: dos ondas largas que nunca paran (más altas con la canción llena)
        float sw = (0.07 + 0.11 * dens) * (0.6 * sin(xw * 1.3 + drift * 1.2 + l * 1.7)
                                         + 0.4 * sin(xw * 2.3 - drift * 0.8 + l * 2.9));
        float pl = pluck(u, hitAge.x, hitAmp.x, hitSeed.x, k, delay)
                 + pluck(u, hitAge.y, hitAmp.y, hitSeed.y, k, delay)
                 + pluck(u, hitAge.z, hitAmp.z, hitSeed.z, k, delay)
                 + pluck(u, hitAge.w, hitAmp.w, hitSeed.w, k, delay);
        float yw = y0 + tilt * xw + sw + bend * pl;
        float ys = (yw - camY) * s;
        // la torsión: la cinta gira sobre su eje; el golpe la retuerce (follow-through)
        float th = xw * twist + drift * (0.6 + 0.2 * l) + l * 1.3 + 1.6 * pl;
        float face = cos(th);
        float wpx = (0.075 + 0.06 * (1.0 - temper)) * s;   // ancho de la cinta
        float hw = abs(face) * wpx * 0.5 + 0.9 * pxw;
        float dy = sp.y - ys;
        float inBand = smoothstep(hw + pxw, hw - pxw, abs(dy));
        // luz desde arriba: la cara que mira a la luz se prende, la de canto es una línea
        float lit = 0.18 + 0.55 * abs(face) * (0.6 + 0.4 * sign(face) * sign(sin(th + 0.6)));
        // fibras finas: con los agudos aparecen hilos que cruzan la cinta y corren
        float fib = smoothstep(0.88, 0.97, sin(xw * 60.0 - drift * 14.0 + l * 3.0) * 0.5 + 0.5) * fizz;
        float ed = (abs(dy) - hw) / (1.1 * pxw);
        float edge = exp(-ed * ed);
        float energy = clamp(abs(pl), 0.0, 1.5);
        vec3 fillC = mix(bg.rgb, ink.rgb, (0.14 + 0.95 * lit) * fog) + hot.rgb * fib * 0.35 * fog;
        vec3 edgeC = mix(ink.rgb, hot.rgb, clamp(0.25 + 0.6 * energy, 0.0, 1.0)) * (0.8 + 0.7 * energy) * fog;
        col = mix(col, fillC, inBand * vis);
        col += edgeC * edge * vis;
        // resplandor de la cinta pulsada (el fósforo se excita con la vibración)
        col += ink.rgb * exp(-abs(dy) / (0.02 * s + 0.004)) * 0.10 * energy * fog * vis;
    }
    col = min(col, vec3(1.0));
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
