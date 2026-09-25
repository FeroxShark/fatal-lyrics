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
    float quality;    // crtQuality: below 1 the chroma low-pass drops to 3 taps
};

layout(binding = 1) uniform sampler2D src;

float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

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
    // and the worn-out tape is 0.6..1 (v goes 0..1, on top of a full k)
    float k = clamp(composite / 0.6, 0.0, 1.0);
    float v = clamp((composite - 0.6) / 0.4, 0.0, 1.0);

    // one screen pixel, in uv. The kernels are laid out in screen pixels so the
    // look does not change with crtQuality.
    float px = 1.0 / max(res.x, 1.0);
    // chroma has a fraction of the luma bandwidth: the wider the tap spread the
    // more the colour bleeds to the side of the thing that carries it
    float sp = (1.0 + 1.5 * k) * px;

    // VHS: the tape does not hold the line still. Head-switching noise at the
    // bottom 3 % (a strip of static and lines that get shoved sideways, worse
    // toward the edge), and tracking that wobbles the whole picture — but only
    // while the tube is glitching: a steady wobble would read as a bad LCD.
    float dx = 0.0;
    float head = 0.0;
    if (v > 0.001) {
        float row = floor(uv.y * res.y);
        float frame = floor(t * 30.0);
        head = smoothstep(0.97, 1.0, uv.y) * v;
        dx += head * ((hash21(vec2(row, frame)) - 0.5) * 0.05 + head * 0.03);
        dx += glitch * v * ((hash21(vec2(floor(row * 0.5), frame * 3.1)) - 0.5) * 0.012
                            + sin(uv.y * 40.0 + t * 50.0) * 0.004);
    }
    vec2 base = vec2(uv.x + dx, uv.y);
    // the colour lags behind the picture by a few pixels
    vec2 cbase = base - vec2(4.0 * v * px, 0.0);

    // luma taps at +-1 px, five chroma taps at +-2 * spread (unrolled: GLSL ES
    // 100 needs a constant loop bound)
    vec3 c0 = texture(src, base).rgb;
    vec3 cl = texture(src, base - vec2(px, 0.0)).rgb;
    vec3 cr = texture(src, base + vec2(px, 0.0)).rgb;
    vec3 q0 = toYiq(c0);
    float yl = dot(cl, LUMA);
    float yr = dot(cr, LUMA);

    vec2 iq;
    if (quality < 0.999) {
        // a slow screen (crtQuality has dropped) gets three taps, and the
        // spread widens a bit to keep the same amount of bleed
        iq = 0.5 * toYiq(texture(src, cbase).rgb).yz;
        iq += 0.25 * toYiq(texture(src, cbase - vec2(1.5 * sp, 0.0)).rgb).yz;
        iq += 0.25 * toYiq(texture(src, cbase + vec2(1.5 * sp, 0.0)).rgb).yz;
    } else {
        iq = 0.4 * toYiq(texture(src, cbase).rgb).yz;
        iq += 0.2 * toYiq(texture(src, cbase - vec2(sp, 0.0)).rgb).yz;
        iq += 0.2 * toYiq(texture(src, cbase + vec2(sp, 0.0)).rgb).yz;
        iq += 0.1 * toYiq(texture(src, cbase - vec2(2.0 * sp, 0.0)).rgb).yz;
        iq += 0.1 * toYiq(texture(src, cbase + vec2(2.0 * sp, 0.0)).rgb).yz;
    }

    // luma with a little ringing: an unsharp kernel overshoots on both sides of
    // an edge, which is what a band-limited signal does
    float y = q0.x + k * 0.55 * (q0.x - 0.5 * (yl + yr));

    // dot crawl: the colour subcarrier leaks into luma on the edges as a
    // checker that changes phase every frame, so it crawls
    float edge = abs(yr - yl);
    // (on the texel grid of the signal texture, so it stays a checker at any
    // crtQuality)
    vec2 pix = floor(uv * res * quality);
    float chk = mod(pix.x + pix.y + floor(t * 15.0), 2.0) * 2.0 - 1.0;
    y += chk * edge * 0.14 * k;
    // and the strip at the bottom is mostly snow
    y += head * (hash21(pix + floor(t * 30.0)) - 0.5) * 0.7;

    vec3 rgb = toRgb(vec3(y, mix(q0.yz, iq, k)));
    fragColor = vec4(clamp(rgb, 0.0, 1.0), 1.0);
}
