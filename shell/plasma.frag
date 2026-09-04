#version 440
// fatal-lyrics — the plasma tube.
//
// Five or six blobs of light drifting inside the glass, joining and pulling
// apart. They are metaballs: each one is a field 1/r², the fields are added
// and the surface is where the sum crosses one. That is what makes two blobs
// MERGE when they come close instead of overlapping — a lamp made of circles
// looks like circles, a lamp made of fields looks like a liquid.
//
// The blobs live in the shader, not in uniforms: their paths are sines on
// periods that do not divide each other, offset by `seed`, so the lamp never
// repeats and no per-blob plumbing crosses the QML boundary.
//
// The music enters twice and both times as motion, never as a flash:
//   · `low` pushes the whole field UP — the bass lifts the wax,
//   · `agit` (the tube's own kick) shakes each blob on its own high-frequency
//     wobble, so a hit ripples the surface instead of blinking it.
//
// The colour is flat palette inside with a `hot` rim: the rim is what reads as
// glowing glass. `count` drops to four on a slow screen — the loop bound stays
// constant (GLSL ES 100 needs it) and the extra blobs are weighted to zero.
//
// Build:  qsb --glsl "100 es,120,150" -o plasma.frag.qsb plasma.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float t;        // seconds since the lamp appeared (already scaled by energy)
    float seed;     // 0..1, re-rolled every appearance: another lamp
    float level;    // overall volume: how bright the wax burns
    float low;      // bass: how high the blobs are pushed
    float agit;     // the kick, decaying: the surface shivers
    float count;    // 4..6 blobs, by crtQuality
    float dim;
    vec2 res;
    vec3 ink;
    vec3 hot;
};

float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float ar = res.x / max(res.y, 1.0);
    vec2 p = vec2((uv.x - 0.5) * ar, uv.y - 0.5);

    // SAFE AREA (T4.1). The glass is the frame minus 4 % of air, and every
    // distance inside is measured against IT. Before, the lamp was a circle of
    // fixed radius (0.78) in aspect-corrected space: on 16:9 it reached 0.74 of
    // a HALF screen in y, so the wax poured out through the top and the bottom,
    // and on the portrait screen it went out through the sides. The blobs stay
    // ROUND — only the tube is the shape of the screen, which is what a tube
    // built into a monitor would be.
    vec2 glass = vec2(0.46 * ar, 0.46);
    float rmin = min(glass.x, glass.y);

    float field = 0.0;
    // Constant bound: GLSL ES 100 will not take a variable one. The blobs past
    // `count` are still walked, they just weigh nothing.
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        float w = step(fi, count - 0.5);
        float s1 = hash11(seed * 57.0 + fi * 13.0);
        float s2 = hash11(seed * 91.0 + fi * 29.0 + 3.0);

        // slow drift on periods that do not divide each other, as a FRACTION
        // of the glass: 0.40 of a half-axis at the very most, so a blob plus its
        // radius can never reach the wall — on any aspect ratio
        vec2 c = glass * vec2(
            (0.30 + 0.10 * s1) * sin(t * (0.17 + 0.043 * fi) + s1 * 6.283),
            (0.26 + 0.12 * s2) * cos(t * (0.11 + 0.037 * fi) + s2 * 6.283)
        );
        // the bass lifts the whole lamp, and the kick shivers each blob apart
        c.y -= low * 0.10 * glass.y;
        c += agit * 0.04 * rmin * vec2(sin(t * 13.0 + fi * 2.1),
                                       cos(t * 11.0 + fi * 1.7));

        float rad = (0.30 + 0.10 * s1) * rmin * (1.0 + 0.15 * agit);
        vec2 d = p - c;
        // 1/r² blows up at the centre of a blob: never divide by nothing
        field += w * rad * rad / max(dot(d, d), 0.0004);
    }

    // the glass: an ellipse inscribed in the safe area, so the wax cannot reach
    // the corners AND cannot leave through an edge
    field *= smoothstep(1.0, 0.42, length(p / glass));

    float e = 0.09;
    float body = smoothstep(1.0 - e, 1.0 + e, field);
    // the rim: bright right at the surface, plain palette deeper in
    float rim = smoothstep(0.94, 1.10, field) * (1.0 - smoothstep(1.12, 1.75, field));

    vec3 col = mix(ink, hot, clamp(rim, 0.0, 1.0)) * (0.80 + 0.40 * level);
    float a = clamp(body * 0.94 * dim, 0.0, 1.0);
    col = clamp(col * dim, 0.0, 1.6);
    fragColor = vec4(col * a, a) * qt_Opacity;   // premultiplied, Qt expects it
}
