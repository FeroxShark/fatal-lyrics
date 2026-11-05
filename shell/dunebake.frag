#version 440
// fatal-lyrics — the noise under the dunes, baked once per seed into a tiling texture: everything in
// the heightfield that is smooth (warp, amp, swell). `dune()` in `dunes.frag` puts the sharp crest
// back with `profile`, so one fetch gives the exact surface, with no blur on the crests.
//
// Build:  qsb --glsl "100 es,120,150" -o dunebake.frag.qsb dunebake.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float seed;
};

float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// `per`: the noise repeats every `per` cells, so the whole heightfield repeats every 100 units and
// can be baked into a tiling texture (see `heightTex`). All frequencies below are per-hundred.
float pnoise(vec2 p, float per) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    vec2 s = vec2(per * 3.17, per * 1.73);
    float a = hash21(mod(i, per) + s);
    float b = hash21(mod(i + vec2(1.0, 0.0), per) + s);
    float c = hash21(mod(i + vec2(0.0, 1.0), per) + s);
    float d = hash21(mod(i + vec2(1.0, 1.0), per) + s);
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void main() {
    vec2 p = qt_TexCoord0 * 100.0;
    vec2 o = vec2(seed * 137.0, seed * 311.0);
    float warp = pnoise(p * 0.13 + o, 13.0) * 3.4 + pnoise(p * 0.37 + o * 1.3, 37.0) * 0.8;
    float amp = 0.34 + 0.85 * pnoise(p * 0.09 - o, 9.0);
    // the swell on top is soft on purpose: a second set of sharp crests zebra-striped every slope
    float swell = pnoise(p * 0.06 + o, 6.0) * 0.28 - 0.1 + pnoise(p * 0.55 + o * 2.1, 55.0) * 0.11;
    // escalados a 0..1: la salida del pase se recorta ahí aunque la textura sea de punto flotante
    fragColor = vec4(warp / 4.2, amp / 1.2, (swell + 0.1) / 0.4, 1.0);
}
