#version 440
// fatal-lyrics — motivo `membrana` (testeo 2026-10-19): el parche de un bombo visto
// en perspectiva, en malla de fósforo. Cada golpe del bombo le pega en un punto y
// la onda viaja hacia afuera con la física del resorte de `Thump.js` (baja, se
// pasa, vuelve, se apaga); los golpes seguidos se SUMAN sobre la cola del anterior.
//
// Dibujo: "voxel space" por columnas, hecho por píxel. Las filas de la malla son
// rectas a profundidad constante de la cámara; se recorren de cerca a lejos y el
// píxel se queda con la primera banda que lo tapa (oclusión correcta: una cresta
// cercana esconde lo que tiene atrás). Las líneas cruzadas salen de las
// coordenadas del parche, que GIRA debajo de la cámara: parallax de verdad.
//
// Build:  /usr/lib/qt6/bin/qsb --glsl '100 es,120,150' -o membrana.frag.qsb membrana.frag
// GLSL 100 es: bucles de cota constante con `break`, sin derivadas, los 4 golpes desenrollados.

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
    vec4 hitSeed;     // dónde pega (0..1)
    vec4 phys;        // (w, wd, zeta·w, 1/rise) del resorte
    vec2 res;
    float physN;      // normalización a pico 1
    float drift;      // fase acumulada de la deriva de fondo
    float dens;       // 0..1 cuán llena está la canción
    float fizz;       // 0..1 agudos que entran
    float temper;     // 0 calmo .. 1 agitado
    float camH;       // altura de la cámara (con el hundimiento del golpe)
    float pitch;      // rad, mirando hacia abajo
    float roll;       // rad
    float yaw;        // rad, el giro del parche
    float waveC;      // velocidad de la onda (unidades de parche por s)
    float rows;       // filas de la malla (≤ 72)
    float depth;      // escala de alto de los golpes
};

const float Z0 = 1.2;
const float Z1 = 9.0;
const float FOCAL = 1.35;

float resp(float age) {
    if (age <= 0.0) return 0.0;
    return (1.0 - exp(-age * phys.w)) * exp(-phys.z * age) * sin(phys.y * age) * physN;
}
float envl(float age) {
    if (age <= 0.0) return 0.0;
    return (1.0 - exp(-age * phys.w)) * exp(-phys.z * age);
}

// aporte de un golpe al punto `m` del parche: (alto, brillo del frente)
vec2 hit(vec2 m, float age, float amp, float sd) {
    if (amp <= 0.0 || age > 6.0) return vec2(0.0);
    float a = sd * 6.2831853;
    vec2 o = vec2(cos(a), sin(a)) * (0.4 + 1.2 * fract(sd * 7.13));
    float r = length(m - o);
    float tau = age - r / waveC;
    // la energía se reparte en un anillo que crece: cae con la distancia
    float spread = amp / (1.0 + 0.7 * r);
    float front = exp(-abs(tau) * 7.0) * step(-0.05, tau);
    return vec2(-resp(tau) * spread, envl(tau) * spread + 0.6 * front * spread);
}

// alto del parche (y brillo de la onda) en coordenadas del parche
vec2 field(vec2 m) {
    // la deriva: dos ondas largas que nunca paran, más grandes cuando la canción se llena
    float sw = (0.05 + 0.07 * dens) * sin(m.x * 0.9 + drift * 1.1) * cos(m.y * 0.7 - drift * 0.8)
             + (0.025 + 0.03 * dens) * sin((m.x - m.y) * 1.9 - drift * 1.7);
    vec2 h = vec2(sw, 0.0);
    h += hit(m, hitAge.x, hitAmp.x, hitSeed.x);
    h += hit(m, hitAge.y, hitAmp.y, hitSeed.y);
    h += hit(m, hitAge.z, hitAmp.z, hitSeed.z);
    h += hit(m, hitAge.w, hitAmp.w, hitSeed.w);
    h.x *= depth;
    // los agudos: un temblor fino que corre por encima (el detalle, no el golpe)
    h.x += 0.018 * fizz * sin(m.x * 23.0 + drift * 9.0) * sin(m.y * 19.0 - drift * 7.0);
    return h;
}

vec2 toPatch(float X, float Z) {
    vec2 q = vec2(X, Z - 5.0);
    float c = cos(yaw), s = sin(yaw);
    return vec2(c * q.x - s * q.y, s * q.x + c * q.y);
}

void main() {
    vec2 frag = qt_TexCoord0 * res;
    vec2 sp = (frag - 0.5 * res) / res.y;
    sp.y = -sp.y;
    float cr = cos(roll), sr = sin(roll);
    sp = vec2(cr * sp.x - sr * sp.y, sr * sp.x + cr * sp.y);

    float cp = cos(pitch), spp = sin(pitch);
    float n = clamp(rows, 8.0, 72.0);

    vec3 col = bg.rgb;
    float prevY = -1e9;
    float prevYf = 0.0;
    float prevZ = Z0;
    vec2 prevH = vec2(0.0);
    bool covered = false;
    float maxY = -1e9;
    float lineAcc = 0.0;
    float bandLit = 0.0;
    float Zhit = Z1;
    vec2 Hhit = vec2(0.0);
    float pxPerUnit = 1.0;
    float rowGap = 1.0;

    for (int i = 0; i < 72; i++) {
        float fi = float(i);
        if (fi >= n) break;
        float Z = Z0 + (Z1 - Z0) * fi / (n - 1.0);
        float d0 = camH * spp + Z * cp;
        float X = sp.x * d0 / FOCAL;
        vec2 h = field(toPatch(X, Z));
        float dz = -(h.x - camH) * spp + Z * cp;
        float Y = ((h.x - camH) * cp + Z * spp) / dz * FOCAL;
        float Yflat = ((-camH) * cp + Z * spp) / d0 * FOCAL;
        // la línea de esta fila: sólo si no la tapa lo de adelante
        float px = abs(sp.y - Y) * res.y;
        if (Y > maxY - 0.5 / res.y) {
            float w = 0.6 + 1.1 * (1.0 - fi / n);
            lineAcc = max(lineAcc, exp(-px * px / (w * w)) * (1.0 - 0.6 * fi / n) * (0.55 + 1.2 * h.y));
        }
        if (Y >= sp.y && maxY < sp.y) {
            // la banda entre la fila anterior y ésta tapa al píxel
            float s = prevY > -1e8 ? clamp((sp.y - prevY) / max(Y - prevY, 1e-5), 0.0, 1.0) : 1.0;
            Zhit = mix(prevZ, Z, s);
            Hhit = mix(prevH, h, s);
            // luz: la banda que se para hacia la cámara (más alta en pantalla que plana) brilla
            bandLit = prevY > -1e8 ? clamp((Y - prevY) / max(Yflat - prevYf, 1e-5), 0.0, 3.0) : 1.0;
            pxPerUnit = FOCAL / d0 * res.y;
            covered = true;
            break;
        }
        maxY = max(maxY, Y);
        prevY = Y;
        prevZ = Z;
        prevH = h;
        prevYf = Yflat;
    }

    float fog = exp(-(Zhit - Z0) * 0.23);
    if (covered) {
        float X = sp.x * (camH * spp + Zhit * cp) / FOCAL;
        vec2 m = toPatch(X, Zhit);
        // malla: líneas del parche (cruzan las filas y giran con él)
        float cell = mix(0.62, 0.34, dens);
        vec2 g = abs(fract(m / cell + 0.5) - 0.5) * cell * pxPerUnit;
        float gl = exp(-min(g.x, g.y) * min(g.x, g.y) / 1.4);
        // nudos que titilan con los agudos
        vec2 id = floor(m / cell + 0.5);
        float tw = fract(sin(dot(id, vec2(12.9898, 78.233)) + floor(drift * 6.0)) * 43758.5453);
        float node = exp(-dot(g, g) / 3.0) * step(1.0 - 0.55 * fizz, tw) * fizz;
        float lit = 0.10 + 0.22 * clamp(bandLit - 0.6, 0.0, 2.0);
        vec3 fill = bg.rgb + ink.rgb * lit * 0.35 * fog;
        float crest = clamp(Hhit.y, 0.0, 1.5);
        vec3 wire = mix(ink.rgb, hot.rgb, clamp(0.25 * crest + 0.8 * node, 0.0, 1.0));
        col = fill + wire * (0.38 * gl * (0.6 + 0.9 * crest) + 1.4 * node) * fog;
    } else {
        // el cielo: un resplandor bajo sobre el horizonte, que respira con la deriva
        float hz = max(sp.y - maxY, 0.0);
        col = bg.rgb + ink.rgb * 0.10 * exp(-hz * 9.0) * (0.7 + 0.3 * sin(drift * 0.9));
    }
    vec3 line = mix(ink.rgb, hot.rgb, clamp(0.3 * Hhit.y, 0.0, 0.8));
    col += line * lineAcc * (covered ? fog * 1.1 + 0.15 : 0.8);
    col = min(col, vec3(1.0));
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
