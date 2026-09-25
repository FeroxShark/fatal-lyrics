#version 440
// fatal-lyrics — CRT mode, first pass: the SIGNAL.
//
// Crt.qml draws the flat lyric layer (`stage`), this pass runs it through the
// cable, and crt.frag then puts the result behind glass. The split exists so
// that everything that acts on the picture BEFORE the glass (composite video
// encoding today; phosphor trail and burn-in later) has a place to live that is
// not the glass shader.
//
// Build:  /usr/lib/qt6/bin/qsb --glsl '100 es,120,150' -o signal.frag.qsb signal.frag
// qsb is not on PATH. Rebuilding is needed whenever you edit this file, and a
// uniform that is not in the .qsb leaves the ShaderEffect property bound to
// nothing, without a warning: check each one with `qsb --dump signal.frag.qsb`.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float t;          // seconds since the mode started
    float composite;  // 0 = clean RGB, 0.5 = old TV, 1 = worn-out VHS
    vec2 res;         // surface size in pixels
    float glitch;     // 0..1 burst
};

layout(binding = 1) uniform sampler2D src;

void main() {
    // clean RGB: the pass is a texel-for-texel copy
    vec4 c = texture(src, qt_TexCoord0);
    // the uniforms that only the composite path reads still have to be
    // referenced or the compiler drops them from the block
    c.rgb += (t + composite + res.x + glitch) * 0.0;
    fragColor = c;
}
