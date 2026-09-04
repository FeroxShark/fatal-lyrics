#version 440
// fatal-lyrics — the static that forms things.
//
// Snow. Not the CRT's own noise (that one sits ON TOP of the picture, in
// `crt.frag`): this is a motif, it IS the picture of a screen with nothing
// tuned in. Once a bar the grain briefly agrees on something — a circle, the
// line number, the first word of the line that is coming — and falls apart
// again. Nothing is ever legible for longer than a beat: it has to read as the
// tube almost catching a signal, not as a caption.
//
// The shape arrives as a mask texture (a hidden Text or circle captured by a
// ShaderEffectSource), so the shader never has to know what it is drawing.
// Inside the mask the grain is FINER and brighter — that is the whole trick.
// Painting the shape as a solid colour would look like a sticker; making the
// noise itself change scale looks like the signal locking.
//
// Build:  qsb --glsl "100 es,120,150" -o static.frag.qsb static.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float t;        // seconds since the static appeared
    float form;     // 0 = pure snow, 1 = the shape has converged
    float seed;     // 0..1, re-rolled every appearance
    float level;    // overall volume: how hot the snow burns
    float high;     // high band: the fine crackle on top
    float dim;
    vec2 res;       // surface size in pixels
    vec3 ink;
    vec3 hot;
};

layout(binding = 1) uniform sampler2D mask;

float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 px = uv * res;

    // The clock is quantised: snow that changes every frame on a 200 Hz screen
    // is a grey wash, because the eye averages it. At ~24 steps a second the
    // grain reads as grain.
    float frame = floor(t * 24.0) + seed * 512.0;

    float m = clamp(texture(mask, uv).a * form, 0.0, 1.0);

    // two grain scales: coarse outside, one pixel inside the shape
    float coarse = hash21(floor(px / 3.0) + vec2(frame, frame * 1.7));
    float fine = hash21(floor(px) + vec2(frame * 2.3, frame));
    float g = mix(coarse, fine, m);

    // a slow horizontal band rolling through, like a tube that never quite
    // locks the frame
    float roll = 0.85 + 0.25 * sin((uv.y + t * 0.13) * 6.283);

    float lum = g * (0.42 + 0.5 * level + 0.25 * high) * roll;
    lum *= 1.0 + 1.25 * m;          // the shape is brighter, not solid
    lum = clamp(lum, 0.0, 1.0);

    vec3 col = mix(ink, hot, clamp(m * 0.75 + g * 0.15, 0.0, 1.0)) * lum;

    float a = clamp(lum * 0.95 * dim, 0.0, 1.0);
    col = clamp(col * dim, 0.0, 1.6);
    fragColor = vec4(col * a, a) * qt_Opacity;   // premultiplied, Qt expects it
}
