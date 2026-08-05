#version 440
// fatal-lyrics — the pond.
//
// The whole screen is the water: a field of loose points, edge to edge,
// vibrating at the frequency of what is playing. It is the old physics-class
// demo — put water on a speaker and the surface stops being flat, it stands
// still in a pattern and shivers in place. Here the register of the song sets
// both the pattern (higher voice, tighter rings and more lobes) and the rate of
// the shiver, the volume sets how violent it is, and each beat drops a stone
// that ripples out and comes back off the edge of the screen.
//
// The standing wave is the point. A travelling wave reads as "an animation
// playing"; a standing one reads as a surface RESONATING, which is what the ear
// is hearing at that moment.
//
// Every dot is its own particle: it has its own idle bob and its own delay
// before a ring reaches it. No mesh, no deformed sheet.
//
// Build:  qsb --glsl 100es,120,150 --hlsl 50 --msl 12 -o pond.frag.qsb pond.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float t;        // seconds since the pond appeared
    float amp;      // how violent the water gets, 0..1
    float pitch;    // register of the song, 0 = bass .. 1 = treble
    float level;    // volume
    float swell;    // low band
    float chop;     // high band
    float speed;    // section energy
    float dim;
    vec2 res;
    vec4 rip1;      // stone: x, y (water coords), start time, strength
    vec4 rip2;
    vec3 ink;
    vec3 hot;
};

// El agua es TODA la pantalla, mirada de arriba: no hay plato ni borde. El
// centro es de donde salen los anillos, y `R` es sólo hasta dónde llega el agua
// (la esquina más lejana), que es contra lo que rebota una piedra.
const float STEP = 0.021;  // lattice spacing
const float DOTR = 0.0050; // dot radius (crests grow, troughs shrink)
const float RIPV = 1.30;   // how fast a stone's ring crosses the water

float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// A stone: the dot only moves once the front arrives, and the front comes back
// off the edge of the picture once — a body of water with a shape, not an
// infinite plane.
float stone(vec2 q, vec4 r, float R) {
    float age = t - r.z;
    if (r.w < 0.001 || age < 0.0 || age > 5.0)
        return 0.0;
    float d0 = distance(q, r.xy);
    float front = age * RIPV;
    float wave = 0.0;
    float d = d0 - front;
    wave += sin(d * 62.0) * exp(-d * d * 340.0);
    // el rebote contra el borde, atenuado
    float d2 = (2.0 * R - d0) - front;
    wave += sin(d2 * 62.0) * exp(-d2 * d2 * 340.0) * 0.45;
    // OJO: la piedra tiene que morir DESPUÉS de que vuelva el rebote. Con el
    // frente a 0.75 y este decaimiento a 1.15, el rebote llegaba a los 2.7 s
    // con el 4% de fuerza: escrito y nunca visto.
    return wave * exp(-age * 0.9) * r.w;
}

// Height of ONE dot of the water.
float surface(vec2 lat, vec2 q, float r, float ang, float R) {
    // La frecuencia es lo que se pidió: el registro de lo que suena decide con
    // qué apretura se para la onda y a qué velocidad tiembla. Nada de esto es
    // la frecuencia real en Hz (a 70 cuadros no se vería), es su lectura: más
    // agudo, más apretado y más rápido.
    float k = 34.0 + 96.0 * pitch;
    float w = 6.2832 * (1.6 + 8.5 * pitch) * speed;
    float lobes = floor(2.0 + 5.0 * pitch);

    // el modo parado: dibujo quieto, temblando en el lugar
    float standing = sin(k * r) * cos(lobes * ang) * sin(w * t);
    // un segundo modo más lento y sin lóbulos, para que el centro no quede
    // siempre planchado
    standing += sin(k * 0.45 * r - w * 0.18 * t) * 0.55 * (0.4 + 0.9 * swell);
    // el picadito de los agudos, fino y desordenado
    standing += sin(k * 1.9 * r + ang * 7.0 + w * 0.6 * t) * 0.22 * chop;

    // cada punto tiene su propio bamboleo: sin esto la superficie entera se
    // mueve como una sola pieza y se ve como una tela, no como agua
    float own = hash21(lat);
    standing += sin(t * speed * (2.1 + 1.7 * own) + own * 6.283) * 0.12;

    // el agua se aquieta un poco hacia el fondo de la pantalla, nada más: no
    // hay pared donde frenarse, el agua sigue afuera del cuadro
    float far = 1.0 - 0.35 * smoothstep(R * 0.55, R, r);

    float h = standing * far * (0.16 + 0.9 * level) * (0.35 + 0.85 * amp);
    h += stone(q, rip1, R) + stone(q, rip2, R);
    return h * 0.030;
}

void main() {
    vec2 uv = qt_TexCoord0;
    float aspect = res.x / max(res.y, 1.0);
    // coordenadas en unidades de ALTO de pantalla, centradas en el plato
    vec2 p = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);
    vec2 q = p;
    // hasta la esquina: es lo lejos que llega el agua que se ve
    float R = length(vec2(aspect * 0.5, 0.5));

    vec3 col = vec3(0.0);
    float a = 0.0;

    vec2 cell = floor(q / STEP);

    for (int dj = -1; dj <= 2; dj++) {
        for (int di = -1; di <= 1; di++) {
            vec2 lat = cell + vec2(float(di), float(dj));
            // filas impares corridas medio paso: agua, no papel cuadriculado
            vec2 qd = vec2((lat.x + 0.5 * mod(lat.y, 2.0)) * STEP, lat.y * STEP);
            float rd = length(qd);

            // la x en pantalla no depende de la altura: descartar por ahí
            // ahorra la superficie entera en la mayoría de los candidatos
            float dx = (p.x - qd.x) * res.y;
            float radMax = DOTR * 1.45 * res.y;
            if (abs(dx) > radMax + 1.5)
                continue;

            float ang = atan(qd.y, qd.x);
            float h = surface(lat, qd, rd, ang, R);

            // la altura levanta el punto en pantalla
            float py = qd.y - h;
            float dy = (p.y - py) * res.y;

            float crest = clamp(h * 30.0 + 0.5, 0.0, 1.0);
            // la cresta además ENGORDA el punto: mirando el agua de arriba, la
            // altura se lee por tamaño y brillo, no por cuánto se corrió
            float rad = DOTR * res.y * (0.72 + 0.62 * crest);

            float dotv = smoothstep(rad, rad * 0.3, length(vec2(dx, dy)));
            if (dotv <= 0.001)
                continue;

            vec3 c = mix(ink, hot, crest * crest);
            // el pozo se APAGA, no se pinta oscuro: un punto más oscuro que el
            // agua se lee como un agujero, y encima se rompe en paleta clara
            float bright = 0.42 + 0.85 * crest;

            col += c * dotv * bright;
            a = max(a, dotv * bright * 0.92);
        }
    }

    a = clamp(a * dim, 0.0, 1.0);
    col = clamp(col * dim, 0.0, 1.6);
    fragColor = vec4(col * a, a) * qt_Opacity;   // premultiplicado, como espera Qt
}
