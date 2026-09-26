#version 440
// fatal-lyrics — CRT mode: the BURN accumulator (tanda 7, corrida 4b).
//
// Runs ONCE per event, never per frame: Crt.qml keeps `burnTex` as a
// non-live, recursive ShaderEffectSource and calls scheduleUpdate() when a
// chorus line (second occurrence or later) has settled on this screen. This
// pass reads the lyric layer alone (`lyr`: the verse text, nothing else),
// turns it into an ink silhouette, and folds it into what was already burnt:
//
//     burn = max(burn * 0.85 - step, silhouette * w(k))
//
// w(k) is the weight of the k-th occurrence (Crt.qml). The result is a single
// 0..1 coverage value; how visible it is (the tint, the `burnin` knob, the
// 5 % / 10 % ceiling) is signal.frag's business, so moving the knob does not
// need a new burn.
//
// Build:  /usr/lib/qt6/bin/qsb --glsl '100 es,120,150' -o burn.frag.qsb burn.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;      // size of the burn texture in pixels
    float weight;  // w(k): how hard this occurrence burns, 0..1
    float fresh;   // 1 = ignore `prev` (nothing burnt yet, or wiped by a new track)
    vec2 sc;       // screen uv -> lyric-texture uv:  (uv - 0.5) * sc + off
    vec2 off;
};

layout(binding = 1) uniform sampler2D lyr;    // ONLY the verse text, transparent elsewhere
layout(binding = 2) uniform sampler2D prev;   // this pass's own last result

// ink coverage 0..1 at a screen uv: the alpha of the lyric layer. Nothing else
// (ghost of the last verse, next line, motif, background) is ever in `lyr`.
float ink(vec2 uv) {
    vec2 l = (uv - 0.5) * sc + off;
    if (l.x < 0.0 || l.y < 0.0 || l.x > 1.0 || l.y > 1.0)
        return 0.0;
    return smoothstep(0.05, 0.35, texture(lyr, l).a);
}

void main() {
    vec2 uv = qt_TexCoord0;
    // `lyr` is remapped and resampled: five taps so a thin stroke does not
    // vanish between samples, and the edge comes out soft (a glow, not a stamp)
    vec2 px = 0.5 / max(res, vec2(1.0));
    float s = ink(uv) * 0.4
        + (ink(uv + vec2(px.x, px.y)) + ink(uv - vec2(px.x, px.y))
         + ink(uv + vec2(px.x, -px.y)) + ink(uv - vec2(px.x, -px.y))) * 0.15;
    // the 8 bit texture parks 0.85/255 back at 1/255 forever: subtract a step
    float p = fresh > 0.5 ? 0.0 : max(texture(prev, uv).r * 0.85 - 1.5 / 255.0, 0.0);
    float v = max(p, s * weight);
    fragColor = vec4(v, v, v, 1.0);
}
