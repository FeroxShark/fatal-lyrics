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
    float persist;    // phosphor persistence 0..1 (0 = no trail, `prev` is not read)
    float dt;         // real seconds since the last time this pass drew
    float light;      // 1 = dark ink on a light face, 0 = light ink on a dark one
    vec4 bg;          // the face background, as it is right now
};

layout(binding = 1) uniform sampler2D src;
layout(binding = 2) uniform sampler2D prev;   // this pass's own last frame

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

// The signal as it comes off the cable, before the phosphor remembers it.
vec3 signalRgb(vec2 uv) {
    // clean RGB: the pass is a texel-for-texel copy
    if (composite < 0.001)
        return texture(src, uv).rgb;

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
    return clamp(rgb, 0.0, 1.0);
}

// Phosphor persistence. What glows keeps glowing for a moment after the signal
// stops asking for it, and it fades per channel: green lasts longest, red and
// blue two thirds of that. `out = max(signal, prev * decay)`, with three details
// that are not optional:
//  - decay is per SECOND (exp2(-dt / halfLife)), not per frame: at 144 Hz a
//    per-frame factor would last half as long as at 60.
//  - a linear step is subtracted on top of the exponential. The texture is 8
//    bit: 1/255 * 0.9 rounds back to 1/255 and never leaves, so a pure
//    exponential parks a permanent smudge on the glass; and the exponential
//    alone needs ~8 half lives to reach 1/255 (700 ms at 90), which is longer
//    than a Motion.enterMs. The step is sized so that a full-white trail is
//    gone by TRAIL_KILL_S, and never under 1.5/255 per frame.
//  - a light face (dark ink) is the same thing turned around: what "glows" is
//    the ink, darker than the background, so the trail is min() and it decays
//    toward the background. Plain max() there would keep the bright background
//    on top of every new letter and fade it in.
const float TRAIL_KILL_S = 0.28;   // < Motion.enterMs (0.32)
const float TRAIL_HALF_S = 0.22;   // green half life at persistence = 1

void main() {
    vec2 uv = qt_TexCoord0;
    vec3 rgb = signalRgb(uv);
    if (persist > 0.001) {
        vec3 half_life = vec3(2.0 / 3.0, 1.0, 2.0 / 3.0) * (persist * TRAIL_HALF_S);
        vec3 d = exp2(-dt / half_life);
        vec3 e = exp2(-TRAIL_KILL_S / half_life);
        vec3 lin = max(e / (1.0 - e) * 0.6931 / half_life * dt, vec3(1.5 / 255.0));
        // `prev` is read at the raw uv: the VHS tracking must not drag the trail
        vec3 p = texture(prev, uv).rgb;
        vec3 dark = max(rgb, p * d - lin);
        vec3 lite = min(rgb, bg.rgb - (bg.rgb - p) * d + lin);
        rgb = mix(dark, lite, light);
    }
    fragColor = vec4(clamp(rgb, 0.0, 1.0), 1.0);
}
