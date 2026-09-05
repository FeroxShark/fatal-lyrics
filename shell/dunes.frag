#version 440
// fatal-lyrics — the dunes.
//
// A desert of loose grains seen from just above the sand, built on the same
// idea as `ocean.frag`: no mesh, every grain is its own point, projected by
// hand with a perspective divide, and its height solved analytically. What
// changes is what the height means — here it is a landscape that does NOT
// move on its own. The dunes are a fixed heightmap; what moves is the camera.
//
// Two things make it never look like the same shot twice:
//   · `seed` re-rolls the noise offsets on every appearance, so the ridges are
//     somewhere else,
//   · the camera pans, creeps forward and rises a little, all on periods that
//     do not divide each other, so it never comes back to a frame it already
//     showed.
//
// The music enters as sand in the air, never as a colour flash:
//   · every beat drops a giant footstep at a random spot and the grains around
//     it are thrown up, fall under gravity and bounce once, small,
//   · in a drop the whole field lifts and HOVERS, jittering a pixel or two at
//     high frequency, and comes down together when the drop ends.
//
// Build:  qsb --glsl "100 es,120,150" -o dunes.frag.qsb dunes.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float t;        // seconds since the dunes appeared
    float seed;     // 0..1, re-rolled every time the motif shows up
    float level;    // overall volume
    float high;     // high band: how hard the hovering sand shivers
    float speed;    // section energy: how fast the camera drifts
    float lift;     // 0..1 drop: the sand rises and stays in the air
    float qual;     // crtQuality: grain spacing, so a slow screen draws fewer
    float dim;      // 1 = the dunes ARE the picture
    vec2 res;       // surface size in pixels
    vec4 jump1;     // footstep: camera-space x and z, start time, strength
    vec4 jump2;     // a second one, so two beats can overlap
    vec3 ink;       // grain colour
    vec3 hot;       // crest colour
};

// --------------------------------------------------------------- the camera
// Eye `camY` above the sand looking flat along it. A grain at (X, h, Z) in
// camera space lands at screen y = HORIZON + (camY - h) / Z, x = X / Z.
//
// T4.2 — THE LATTICE IS GEOMETRIC, NOT EVENLY SPACED IN Z. Rows used to sit
// every DZ = 0.135 world units, so their spacing ON SCREEN fell off as 1/Z^2:
// by Z = 8 four rows landed on the same pixel and what you saw at the horizon
// was a moire staircase, not sand. Now Z_j = Z0 * exp((j - drift) * KZ), which
// puts the rows a constant RATIO apart — their screen spacing shrinks
// proportionally to the height above the horizon, which is what perspective
// actually does, and no two rows ever collapse into one. The forward drift
// works out too: dZ/dt is proportional to Z, so on screen the near rows run
// fast and the far ones creep.
//
// The columns follow: the horizontal step grows with Z (DXr = DX * Z / Z0), so
// the grains keep the same spacing on screen all the way back instead of
// crowding. That alone would line them up in perfect vertical columns, so each
// row gets its own horizontal offset from a hash — a stagger of 0.5 every other
// row (what was here before) reads as a woven grid at this density.
const float Z0 = 1.30;    // first row of grains still on screen
const float ZMAX = 34.0;  // the last row that draws anything at all
const float GRAINR = 0.020;
const float GRAV = 3.2;   // how fast a thrown grain comes back down
const float BOUNCE = 0.42;

float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// value noise, smooth enough that the dunes read as sand and not as facets
float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// The landscape. Three octaves is where a ridge stops looking like a bump and
// starts looking like a dune with a windward side; a fourth costs the same as
// the whole projection and nobody sees it at this dot density.
float dune(vec2 p) {
    vec2 o = vec2(seed * 137.0, seed * 311.0);
    float h = vnoise(p * 0.45 + o) * 0.62;
    h += vnoise(p * 1.10 + o * 1.7) * 0.26;
    h += vnoise(p * 2.60 + o * 2.9) * 0.12;
    return (h - 0.5) * 0.34;
}

// A giant footstep: the grains near it are thrown up, fall, and bounce once.
// The falloff is what makes it a footstep and not the whole desert jumping.
// `p` here is the grain in CAMERA space — see the call site.
float footstep(vec2 p, vec4 j) {
    float age = t - j.z;
    if (j.w < 0.001 || age < 0.0 || age > 3.0)
        return 0.0;
    float d = distance(p, j.xy);
    float near = exp(-d * d * 0.55);
    if (near < 0.01)
        return 0.0;
    float v0 = (0.42 + 0.5 * level) * j.w * near;
    float flight = 2.0 * v0 / GRAV;
    if (age < flight)
        return v0 * age - 0.5 * GRAV * age * age;
    float v1 = v0 * BOUNCE;
    float a2 = age - flight;
    float flight2 = 2.0 * v1 / GRAV;
    if (a2 < flight2)
        return v1 * a2 - 0.5 * GRAV * a2 * a2;
    return 0.0;
}

void main() {
    vec2 uv = qt_TexCoord0;
    float aspect = res.x / max(res.y, 1.0);
    float sx = (uv.x - 0.5) * aspect;
    // T4.3b: en la pantalla vertical el horizonte a 0.30 deja 576 px de cielo
    // vacío arriba y la arena arranca a media pantalla. Sube a 0.22 cuando el
    // monitor es más alto que ancho.
    float HORIZON = res.y > res.x ? 0.22 : 0.30;
    float dy = uv.y - HORIZON;

    // The drift. Three periods that do not line up: the shot never repeats.
    float tt = t * max(speed, 0.35);
    float camX = tt * 0.045 + sin(tt * 0.031 + seed * 6.283) * 1.6;
    float camZ = tt * 0.075;
    float camY = 1.0 + 0.16 * sin(tt * 0.021 + seed * 3.1);

    // grain spacing. KZ is the RATIO between one row and the next, not a
    // distance: 0.095 puts the first two rows 0.13 apart, which is what the old
    // constant step gave near the eye.
    float q = clamp(qual, 0.45, 1.0);
    float KZ = 0.095 / q;
    // T4.2 — LAS COLUMNAS SIGUEN EN EL MUNDO, NO EN LA PANTALLA. Un intento
    // anterior escaló también el paso horizontal con Z (DX * Z / Z0) para que
    // los granos guardaran la misma separación en pantalla: el resultado son
    // COLUMNAS VERTICALES PERFECTAS, sin punto de fuga, y en la vertical cinco
    // granos por fila (medido en /tmp/dw-a-*.png). La perspectiva de verdad es
    // que las filas de atrás tengan MÁS granos, no los mismos. El paso queda en
    // unidades de mundo; el amontonamiento lejano lo resuelve el `fade`, no el
    // muestreo.
    //
    // El ancho de mundo que entra en la pantalla es proporcional al aspecto:
    // con el mismo DX la vertical (aspect 0.56) tendría la mitad de granos por
    // fila que la apaisada. El clamp la acerca sin agrandar la apaisada.
    float DX = 0.165 / q * clamp(aspect, 0.62, 1.0);

    // ------------------------------------------------------------- el cielo
    // T4.2c/d: el horizonte era una raya encendida (dos exponenciales en |dy|),
    // que es exactamente la banda clara que Ferox vio partiendo el cuadro al
    // medio. El horizonte de un desierto no es una raya: es donde la niebla y
    // el suelo se tocan. Así que el cielo es un degradado vertical — oscuro
    // arriba, tibio contra el suelo — y la MISMA niebla sigue por debajo del
    // horizonte y se apaga hacia abajo con `smoothstep`, cuya derivada es cero
    // en dy = 0: sin derivada no hay canto, y por eso no hay banda.
    float skyT = clamp(1.0 - max(-dy, 0.0) / max(HORIZON, 0.001), 0.0, 1.0);
    skyT = skyT * skyT;
    vec3 hazeCol = ink * (0.16 + 0.14 * level);
    vec3 skyCol = mix(ink * 0.03, hazeCol, skyT);
    float skyA = mix(0.04, 0.17, skyT) * (0.7 + 0.4 * level);
    if (dy > 0.0) {
        skyCol = hazeCol;
        skyA = 0.17 * (0.7 + 0.4 * level) * (1.0 - smoothstep(0.0, 0.34, dy));
    }

    // OJO: la salida es premultiplicada (`col * a`), así que acá `col` va SIN
    // multiplicar por su propia cobertura — si no, el cielo sale con el alfa
    // al cuadrado y no se ve.
    vec3 col = skyCol;
    float a = skyA;

    if (dy > 0.0008) {
        float z = camY / dy;              // depth of flat sand under this pixel
        if (z > 0.0 && z < ZMAX * 1.3) {
            // el corrimiento hacia adelante. `n` es el índice de la fila en el
            // MUNDO: sin él, `drift` da la vuelta cada vez que la cámara avanza
            // Z0*KZ (1.6 s) y todas las semillas de las filas se renumeran al
            // mismo tiempo — la arena entera cambiaba de lugar de golpe, que es
            // "cambia sin razón". Con `jw` la identidad de la fila sobrevive al
            // salto del índice local.
            float dnum = camZ / (Z0 * KZ);
            float drift = fract(dnum);
            float n = floor(dnum);
            float jf = log(z / Z0) / KZ + drift;
            int j0 = int(floor(jf));

            for (int dj = -2; dj <= 2; dj++) {
                // low quality also looks at fewer neighbouring rows: the far
                // ones are the expensive half and the ones nobody can resolve
                if (q < 0.8 && (dj < -1 || dj > 1))
                    continue;
                int j = j0 + dj;
                float Z = Z0 * exp((float(j) - drift) * KZ);
                if (Z < 0.55 || Z > ZMAX)
                    continue;
                float jw = float(j) + n;

                // T4.2b: el grano se apaga ANTES de tocar el horizonte, y llega
                // a CERO. La exponencial de antes (exp(-(Z-Z0)*0.13)) nunca
                // llegaba, así que siempre quedaba un resto amontonado sobre la
                // línea del horizonte: eso era el escalón.
                float fade = smoothstep(ZMAX, ZMAX * 0.55, Z);
                if (fade <= 0.002)
                    continue;

                // el corrimiento horizontal de la fila: sin él las filas quedan
                // alineadas en columnas y la arena se lee como una malla.
                float stagger = hash21(vec2(jw, 3.7));
                float ifl = sx * Z / DX - stagger;
                int i0 = int(floor(ifl));

                float rad = clamp(GRAINR / Z * res.y, 0.7, res.y * 0.010) * mix(0.55, 1.0, fade);
                if (rad < 0.3)
                    continue;

                for (int di = -1; di <= 1; di++) {
                    int i = i0 + di;
                    float X = (float(i) + stagger) * DX;
                    float px = X / Z;
                    float dx = (sx - px) * res.y;
                    if (abs(dx) > rad + 1.0)
                        continue;

                    // world position of this grain: the lattice is in CAMERA
                    // space and the landscape is not, so the camera offset goes
                    // in here. Without it the dunes would travel with the eye
                    // and nothing would ever come closer.
                    vec2 wp = vec2(X + camX, Z + camZ);
                    float own = hash21(vec2(float(i), jw));
                    float h = dune(wp);
                    // The footstep is measured in CAMERA space, not world
                    // space: it lasts three seconds and has to stay where it
                    // landed on screen. In world space the pan would carry it
                    // off frame.
                    h += footstep(vec2(X, Z), jump1) + footstep(vec2(X, Z), jump2);
                    // the drop: the field hangs in the air, shivering. The
                    // shiver is in world units, sized so it lands on one or two
                    // pixels at the depth where most of the grains are.
                    h += lift * (0.20 + 0.10 * own);
                    h += lift * sin(t * 38.0 + own * 6.283) * 0.0035 * (0.4 + high);

                    float py = HORIZON + (camY - h) / Z;
                    vec2 d = vec2(dx, (uv.y - py) * res.y);
                    float g = smoothstep(rad, rad * 0.3, length(d));
                    if (g <= 0.001)
                        continue;

                    // the ridge catches the light; the trough only dims. A
                    // grain drawn darker than the sand reads as a hole in the
                    // picture.
                    float crest = clamp(h * 6.0 + 0.5, 0.0, 1.0);
                    vec3 c = mix(ink, hot, crest * crest);
                    float bright = (0.42 + 0.8 * crest) * fade;
                    // la niebla: el grano lejano se va HACIA el color del cielo
                    // en función de la DISTANCIA, no del |dy|. Así no hay
                    // ninguna línea: la arena se disuelve en el aire.
                    c = mix(hazeCol, c, fade);

                    col += c * g * bright;
                    a = max(a, g * bright * 0.92);
                }
            }
        }
    }

    a = clamp(a * dim, 0.0, 1.0);
    col = clamp(col * dim, 0.0, 1.6);
    fragColor = vec4(col * a, a) * qt_Opacity;   // premultiplied, Qt expects it
}
