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

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

// RGB <-> YIQ, the NTSC colour space: what travels down the cable is a luma
// signal plus a colour subcarrier that is allowed much less bandwidth.
vec3 toYiq(vec3 c) {
    return vec3(dot(c, LUMA),
                dot(c, vec3(0.596, -0.274, -0.322)),
                dot(c, vec3(0.211, -0.523, 0.312)));
}
vec3 toRgb(vec3 q) {
    return vec3(q.x + 0.956 * q.y + 0.621 * q.z,
                q.x - 0.272 * q.y - 0.647 * q.z,
                q.x - 1.106 * q.y + 1.703 * q.z);
}

void main() {
    vec2 uv = qt_TexCoord0;
    // clean RGB: the pass is a texel-for-texel copy
    if (composite < 0.001) {
        fragColor = texture(src, uv);
        return;
    }

    // `composite` is 0..1; the TV half of the range is 0..0.6 (k goes 0..1)
    float k = clamp(composite / 0.6, 0.0, 1.0);

    // one screen pixel, in uv. The kernels are laid out in screen pixels so the
    // look does not change with crtQuality.
    float px = 1.0 / max(res.x, 1.0);
    // chroma has a fraction of the luma bandwidth: the wider the tap spread the
    // more the colour bleeds to the side of the thing that carries it
    float sp = (1.0 + 1.5 * k) * px;

    // luma taps at +-1 px, five chroma taps at +-2 * spread (unrolled: GLSL ES
    // 100 needs a constant loop bound)
    vec3 c0 = texture(src, uv).rgb;
    vec3 cl = texture(src, uv - vec2(px, 0.0)).rgb;
    vec3 cr = texture(src, uv + vec2(px, 0.0)).rgb;
    vec3 q0 = toYiq(c0);
    float yl = dot(cl, LUMA);
    float yr = dot(cr, LUMA);

    vec2 iq = 0.4 * q0.yz;
    iq += 0.2 * toYiq(texture(src, uv - vec2(sp, 0.0)).rgb).yz;
    iq += 0.2 * toYiq(texture(src, uv + vec2(sp, 0.0)).rgb).yz;
    iq += 0.1 * toYiq(texture(src, uv - vec2(2.0 * sp, 0.0)).rgb).yz;
    iq += 0.1 * toYiq(texture(src, uv + vec2(2.0 * sp, 0.0)).rgb).yz;

    // luma with a little ringing: an unsharp kernel overshoots on both sides of
    // an edge, which is what a band-limited signal does
    float y = q0.x + k * 0.55 * (q0.x - 0.5 * (yl + yr));

    // dot crawl: the colour subcarrier leaks into luma on the edges as a
    // checker that changes phase every frame, so it crawls
    float edge = abs(yr - yl);
    vec2 pix = floor(uv * res);
    float chk = mod(pix.x + pix.y + floor(t * 15.0), 2.0) * 2.0 - 1.0;
    y += chk * edge * 0.14 * k;

    vec3 rgb = toRgb(vec3(y, mix(q0.yz, iq, k)));
    fragColor = vec4(clamp(rgb, 0.0, 1.0), 1.0);
}
