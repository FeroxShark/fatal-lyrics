#version 440
// fatal-lyrics — the inkblot.
//
// A symmetric blot that breathes with the song. It is a field of value noise
// with a threshold on it, and the symmetry is free: every coordinate is a
// function of `abs(x - 0.5)`, so whatever the noise does on the right happens
// on the left by construction. Folding the picture afterwards would need a
// second pass; folding the COORDINATE costs nothing.
//
// What the music does to it, and why in this order:
//   · the threshold drops with `level`, so a loud passage grows the blot
//     outwards instead of just brightening it — a blot that only changes
//     colour reads as a light, one that changes SHAPE reads as ink,
//   · the noise drifts with the clock, so the edges creep,
//   · `pitch` twists the domain around the centre: the same blot, wrung,
//   · a kick makes it SPLASH — the threshold falls for about one frame and
//     the ink jumps out and comes back.
//
// Two tones only, like a plate printed twice: the body in `ink`, the deep
// part in `hot`. A gradient here would look like a lava lamp, which is the
// next motif over and a different idea.
//
// FAMILIES (T3.B2). Every plate used to be one round mass wobbling, so Ferox
// saw "siempre una bola". The silhouette now comes from five parameters, and a
// family is a set of values for them: spikes (high-frequency noise on the
// threshold), lobes (the falloff hangs from two centres instead of one), holes
// (a second, inverted threshold eats the body), elongated (anisotropy before
// the noise) and splattered (small islands around the mass). They are
// PARAMETERS and not five branches on purpose: crossfading between families is
// then a lerp of six numbers, done in QML with a Behavior, and the shader stays
// one evaluation. Two evaluations mixed would be sixteen octaves of fbm per
// pixel to change a silhouette.
//
// Build:  qsb --glsl "100 es,120,150" -o rorschach.frag.qsb rorschach.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float t;        // seconds since the blot appeared
    float seed;     // 0..1, re-rolled every appearance: another plate
    float level;    // overall volume: how far the ink spreads
    float pitch;    // 0 low .. 1 high: the twist
    float splash;   // 1 on a kick, decaying: the ink jumps
    float dim;
    // the family, as parameters (see above). All of them are tweened in QML.
    float famSpike; // ripple on the threshold: a spiky edge
    float famLobe;  // how far apart the two centres of the falloff sit
    float famHole;  // how much of the body the inverted threshold eats
    float famSx;    // anisotropy: > 1 squeezes in x, so the blot stretches
    float famSy;
    float famSpat;  // islands scattered around the mass
    vec2 res;
    vec3 ink;
    vec3 hot;
};

float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

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

// Four octaves. Three leaves an edge too smooth to read as ink; five only
// adds specks that the tube's own grain eats anyway.
float fbm(vec2 p) {
    float v = 0.0;
    float amp = 0.55;
    for (int i = 0; i < 4; i++) {
        v += vnoise(p) * amp;
        p = p * 2.03 + vec2(19.1, 7.3);
        amp *= 0.5;
    }
    return v;
}

void main() {
    vec2 uv = qt_TexCoord0;
    // squarish domain, so the blot is not stretched on a wide screen
    float ar = res.x / max(res.y, 1.0);

    // The fold comes FIRST: everything downstream is a function of the folded
    // coordinate, so the twist cannot break the symmetry.
    vec2 q = vec2(abs(uv.x - 0.5) * ar, uv.y - 0.5);

    // the wring: more turn the further out, so the middle stays put
    float ang = (pitch - 0.5) * 1.6 * length(q);
    float ca = cos(ang), sa = sin(ang);
    q = mat2(ca, -sa, sa, ca) * q;

    // elongated: the squeeze goes in BEFORE the noise, so the grain stretches
    // with the shape instead of a round blot being scaled afterwards
    q *= vec2(famSx, famSy);

    vec2 off = vec2(seed * 91.0, seed * 47.0);
    float f1 = fbm(q * 3.4 + off + vec2(0.0, t * 0.06));
    float f2 = fbm(q * 1.3 - off * 0.7 - vec2(t * 0.035, 0.0));
    float n = (f1 + 0.35 * f2) / 1.35;

    // spiky: a fast ripple straight on the value, which is the same as moving
    // the threshold about, so the edge frays without the body moving
    n += famSpike * (vnoise(q * 21.0 + off) - 0.5);

    // the blot has to end somewhere: a soft round falloff, or the ink reaches
    // the corners and it stops being a blot and becomes a texture. With
    // `famLobe` it hangs from two centres up and down the spine, and the mass
    // splits in two.
    vec2 qa = q - vec2(famLobe * 0.22, -famLobe);
    vec2 qb = q - vec2(famLobe * 0.22, famLobe);
    float r = min(length(qa * vec2(1.0, 1.12)), length(qb * vec2(1.0, 1.12)));
    n *= smoothstep(0.62, 0.12, r);
    // and it hangs from the middle, like a plate folded down the spine
    n *= 0.75 + 0.35 * smoothstep(0.30, 0.0, abs(q.x));

    // splattered: islands of their own around the mass, on the same fold, so
    // they are mirrored too
    float isl = vnoise(q * 8.5 - off * 1.7 + vec2(t * 0.02, 0.0));
    n += famSpat * smoothstep(0.62, 0.95, isl) * smoothstep(0.95, 0.20, r);

    float thr = 0.30 - 0.10 * level - 0.09 * splash;
    float w = 0.020 + 0.010 * splash;      // the edge, antialiased
    float body = smoothstep(thr - w, thr + w, n);
    float core = smoothstep(thr + 0.055 - w, thr + 0.055 + w, n);

    // holed: the SECOND octave, thresholded the other way round, bites the body
    // open. It is the same noise the blot is made of, so the holes belong to it.
    float hole = smoothstep(0.46, 0.60, f2);
    body *= 1.0 - famHole * hole;
    core *= 1.0 - famHole * hole;

    vec3 col = mix(ink, hot, core) * (0.85 + 0.35 * level);
    float a = clamp(body * (0.92 * dim), 0.0, 1.0);
    col = clamp(col * dim, 0.0, 1.6);
    fragColor = vec4(col * a, a) * qt_Opacity;   // premultiplied, Qt expects it
}
