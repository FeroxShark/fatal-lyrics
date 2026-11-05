#version 440
// fatal-lyrics — the heightfield of the dunes, baked once per seed into a tiling texture so the march
// in `dunes.frag` can read it with one fetch per step. `dune()` here and there have to be the same.
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

// One dune seen across the wind: long windward slope, then the crest, then a short slip face.
// The phase is continuous everywhere and the profile is 0 at both ends, so nothing breaks at the
// wrap of `fract`.
float profile(float u) {
    float saw = fract(u);
    const float CREST = 0.70;
    float wind = saw / CREST;
    wind = wind * wind * (1.6 - 0.6 * wind);
    float slip = (1.0 - saw) / (1.0 - CREST) * 0.72;
    // a crest is sharp but not a knife: without this rounding the ray slips past the edge
    const float K = 0.05;
    float m = clamp(0.5 + 0.5 * (slip - wind) / K, 0.0, 1.0);
    return mix(slip, wind, m) - K * m * (1.0 - m);
}

// The heightfield. The domain warp is what bends the crests into long curves, and the height of
// each one varies along it, so a crest dies out and another one takes over, as they do.
// COPIED in `dunebake.frag`: the two have to agree (test_shaders_motivos).
float dune(vec2 p) {
    vec2 o = vec2(seed * 137.0, seed * 311.0);
    float warp = pnoise(p * 0.13 + o, 13.0) * 3.4 + pnoise(p * 0.37 + o * 1.3, 37.0) * 0.8;
    float amp = 0.34 + 0.85 * pnoise(p * 0.09 - o, 9.0);
    // the swell on top is soft on purpose: a second set of sharp crests zebra-striped every slope
    return profile(p.x * 0.15 + p.y * 0.19 + warp * 0.55) * amp + pnoise(p * 0.06 + o, 6.0) * 0.28 - 0.1
         + pnoise(p * 0.55 + o * 2.1, 55.0) * 0.11;
}

void main() {
    fragColor = vec4(dune(qt_TexCoord0 * 100.0), 0.0, 0.0, 1.0);
}
