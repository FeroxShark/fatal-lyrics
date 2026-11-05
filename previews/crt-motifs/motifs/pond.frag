#version 440
// fatal-lyrics — the pond.
//
// Water on a speaker, seen from above: the old physics-class demo. The surface stops being flat and
// stands still in a pattern, shivering in place. The register of the song sets the pattern (higher
// voice, tighter rings and more lobes) and the rate of the shiver, the volume how violent it is, and
// each beat drops a stone that ripples out and comes back off the far edge. A standing wave reads as
// a surface RESONATING, which is what the ear is hearing at that moment.
//
// It was a lattice of dots and read as a lattice (Ferox 2026-11-05). What reads as water from above
// is LIGHT: the slope of the surface bends a lamp's reflection across it and focuses it on the
// bottom (caustics), so all of this is computed from the height's gradient and nothing is drawn.
//
// Build:  qsb --glsl "100 es,120,150" -o pond.frag.qsb pond.frag

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
    vec4 view;      // WALL: p = view.xy + qt_TexCoord0 · view.zw, in units of `span` from the canvas centre
    vec4 wcfg;      // WALL: x = 1 on the wall, y = px per unit, z = reach of the water (R)
    vec2 fo;        // WALL: where the rings come from (the text screen, or the middle), same units
};

// El agua es TODA la pantalla, mirada de arriba: no hay plato ni borde. El centro es de donde salen
// los anillos, y `R` es sólo hasta dónde llega (la esquina más lejana), contra lo que rebota.
const float RIPV = 1.30;   // how fast a stone's ring crosses the water

float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// A stone: the front comes back off the edge of the picture once. It has to die AFTER the bounce
// returns, or the bounce is written and never seen.
float stone(vec2 q, vec4 r, float R) {
    float age = t - r.z;
    if (r.w < 0.001 || age < 0.0 || age > 5.0)
        return 0.0;
    float d0 = distance(q, r.xy);
    float front = age * RIPV;
    float d = d0 - front;
    float wave = sin(d * 46.0) * exp(-d * d * 120.0);
    float d2 = (2.0 * R - d0) - front;
    wave += sin(d2 * 46.0) * exp(-d2 * d2 * 120.0) * 0.45;
    return wave * exp(-age * 0.9) * r.w;
}

// The height of the water at `q` (relative to where the rings come from).
float surface(vec2 q, float R) {
    float r = length(q);
    float ang = atan(q.y, q.x);
    // Not the real frequency in Hz, its reading: higher voice, tighter and faster.
    float k = 22.0 + 58.0 * pitch;
    float w = 6.2832 * (0.7 + 2.6 * pitch);
    float lobes = floor(2.0 + 5.0 * pitch);

    float h = sin(k * r) * cos(lobes * ang) * sin(w * t);
    // a slower mode with no lobes, so the centre is never ironed flat
    h += sin(k * 0.45 * r - w * 0.42 * t) * 0.55 * (0.4 + 0.9 * swell);
    // a wind that belongs to no mode: without it the pattern is too clean to be water
    h += (vnoise(q * 9.0 + vec2(t * 0.34, -t * 0.27)) - 0.5) * 0.9;
    h += sin(k * 1.9 * r + ang * 7.0 + w * 0.8 * t) * 0.20 * chop;

    float far = 1.0 - 0.35 * smoothstep(R * 0.55, R, r);
    h *= far * (0.20 + 0.9 * level) * (0.35 + 0.85 * amp);
    h += (stone(q, rip1, R) + stone(q, rip2, R)) * 1.6;
    return h * 0.0042;
}

void main() {
    vec2 uv = qt_TexCoord0;
    float aspect = res.x / max(res.y, 1.0);
    vec2 p = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);
    float R = length(vec2(aspect * 0.5, 0.5));
    vec2 o = vec2(0.0);
    // PARED (docs/PARED.md): UN lienzo. `p` es la ventana de esta pantalla en el lienzo común, los
    // anillos salen del foco `fo` y cruzan las pantallas; `R` es lo lejos que llega el agua.
    if (wcfg.x > 0.5) {
        p = view.xy + uv * view.zw;
        R = wcfg.z;
        o = fo;
    }
    vec2 q = p - o;

    // the slope, by differences: everything below is what it does to the light
    const float E = 0.0016;
    float h0 = surface(q, R);
    vec2 g = vec2(surface(q + vec2(E, 0.0), R) - h0, surface(q + vec2(0.0, E), R) - h0) / E;

    // the bottom, seen through the water: refraction moves it with the slope, and the caustic web
    // is that same displacement converging. Two layers at different scales, drifting apart.
    vec2 b = p + g * 0.16;
    float warp = vnoise(b * 5.0 + vec2(t * 0.10, 2.0)) + vnoise(b * 5.0 - vec2(t * 0.08, -7.0));
    float n1 = vnoise(b * 10.0 + warp * 1.7 + t * 0.06);
    float n2 = vnoise(b * 16.0 - warp * 1.3 - t * 0.05);
    float web = clamp(1.0 - abs(n1 * 2.0 - 1.0), 0.0, 1.0);
    web = pow(web, 9.0) + pow(clamp(1.0 - abs(n2 * 2.0 - 1.0), 0.0, 1.0), 12.0) * 0.6;
    float focus = web * (0.55 + 1.2 * clamp(dot(g, g) * 30.0, 0.0, 1.0));

    // the bottom darkens away from the middle, the way a lit pool does
    float bowl = 1.0 - 0.45 * smoothstep(0.1, R, length(q));
    vec3 water = ink * (0.12 + 0.10 * n1) * bowl;
    water += mix(ink, hot, 0.25) * focus * 0.30 * (0.55 + 0.6 * level);
    // the relief itself, lit from one side: this is what shows the rings and the lobes
    water += ink * clamp(dot(g, vec2(0.74, -0.67)) * 3.4, -0.11, 0.62) * bowl;

    // the lamp above, off to one side: its long, wobbling reflection and the sheen of each ripple
    vec3 n = normalize(vec3(-g.x, 1.0, -g.y));
    vec3 lamp = normalize(vec3(0.44, 1.0, -0.38));
    vec3 hv = normalize(lamp + vec3(0.0, 1.0, 0.0));
    float sp = max(dot(n, hv), 0.0);
    float glint = pow(sp, 340.0) * 1.15 + pow(sp, 46.0) * 0.17;
    vec3 col = water + hot * glint;
    // the crests catch a little of the colour
    col += ink * clamp(h0 * 90.0, 0.0, 1.0) * 0.16;

    float a = clamp(0.86 + glint + focus * 0.3, 0.0, 1.0);
    a = clamp(a * dim, 0.0, 1.0);
    col = clamp(col * dim, 0.0, 1.6);
    fragColor = vec4(col * a, a) * qt_Opacity;   // premultiplicado, como espera Qt
}
