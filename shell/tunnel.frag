#version 440
// fatal-lyrics — the tunnel.
//
// Rings coming at the camera, the oldest demo trick there is: in polar
// coordinates, depth is 1/r. Take `fract` of it and you get evenly spaced
// rings that bunch up towards the middle exactly the way perspective bunches
// them, without a single vertex.
//
// Two rules this one is built around, because the tunnel that was tried in an
// earlier pass came out BLANK and got removed:
//   · `t` is TRAVELLED DISTANCE, accumulated up in QML, not a clock multiplied
//     by speed. Multiplying a clock by speed means every change of volume
//     teleports every ring, because the clock is hundreds of seconds by then,
//   · nothing here depends on the tube moving. With the screen still, `t` stops
//     and the shader still draws a complete frame of rings. Still, never empty.
//
// Framing: measured at 9:16, 16:9 and 21:9, the mouth never gets closer than
// 0.24 of the frame to an edge, and `far` is 1 at every corner — so the ring
// pattern reaches the corners and no zoom of the camera can uncover a hole.
//
// The music: `level` is how fast the rings arrive (up in QML), `twist` wrings
// them around the axis — and the wring grows with depth, so the far end of the
// tunnel turns more than the mouth — and the centre drifts on its own slow
// clock, which is what keeps it from looking like a target painted on glass.
//
// CONTRAST (T3.B8). The first version had a wide soft plateau per ring, and at
// any distance that reads as one gradient: Ferox saw "casi no hay contraste
// entre los anillos". Now a ring is a THIN hot edge over a near-black floor,
// there is a vignette so the mouth falls off at the corners as well as at the
// far end, and every kick plants a lit ring that flies out with the others.
//
// The pulse costs nothing to move: a constant value of `depth` travels outwards
// by itself, because `depth = 0.42/r + t` and `t` grows — so a ring planted at
// a depth stays at that depth and its radius opens up. The beat only has to say
// WHERE to plant it.
//
// Build:  qsb --glsl "100 es,120,150" -o tunnel.frag.qsb tunnel.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float t;        // distance travelled down the tunnel (NOT a clock × speed)
    float ct;       // plain seconds: only the centre drift uses this
    float twist;    // -0.5..0.5, from pitch: the wring
    float seed;     // 0..1, re-rolled every appearance
    float level;    // overall volume: how hot the walls burn
    float pulseDepth; // where the lit ring was planted, in depth
    float pulseAmt;   // 1 on a kick, decaying
    float dim;
    vec2 res;
    vec3 ink;
    vec3 hot;
};

void main() {
    vec2 uv = qt_TexCoord0;
    float ar = res.x / max(res.y, 1.0);

    // The mouth wanders on two periods that do not divide each other, so it
    // never comes back to where it was — but the drift is measured as a
    // fraction of the FRAME and clamped to 15% of the half-frame on each
    // axis. A fixed number here is not a fixed fraction: this space is
    // stretched by the aspect, so on a portrait screen (`ar` around 0.56)
    // half the width is 0.28 and an 0.08 drift was almost a third of it —
    // the mouth walked out of the picture.
    vec2 halfFrame = vec2(0.5 * ar, 0.5);
    vec2 drift = vec2(sin(ct * 0.13 + seed * 6.283),
                      cos(ct * 0.091 + seed * 4.11));
    vec2 centre = clamp(drift, -1.0, 1.0) * halfFrame * 0.15;
    vec2 p = vec2((uv.x - 0.5) * ar, uv.y - 0.5) - centre;

    // 1/r is the depth. Never divide by nothing: at the exact centre that is a
    // NaN, and a NaN is a hole punched in the picture.
    float r = max(length(p), 0.0015);
    float ang = atan(p.y, p.x) / 6.283185;

    // The 2.0 sets how many rings fit on screen: with the old 0.42 there were
    // barely two and a half between the mouth and the far end, which with a
    // thin edge profile leaves a black field with a couple of hoops in it.
    float depth = 2.0 / r + t;
    // the wring grows with depth: the far end turns more than the mouth
    float a = ang + twist * depth * 0.11;

    // A ring is an EDGE, not a plateau: `d0` is 0 in the middle of a ring and 1
    // on its boundary, and only the last fifth of that lights up. Between two
    // rings the wall stays near black, which is the whole difference between a
    // tunnel and a lamp shade.
    float d0 = abs(fract(depth) - 0.5) * 2.0;
    float edge = smoothstep(0.72, 1.0, d0);
    float stave = fract(a * 10.0);
    float staveEdge = smoothstep(0.0, 0.10, stave) * (1.0 - smoothstep(0.72, 1.0, stave));

    // brick parity: alternate the tone ring by ring, so the walls have a grain
    float parity = mod(floor(depth) + floor(a * 10.0), 2.0);

    // the floor is not black-black — a tunnel with nothing between the rings is
    // a set of hoops floating in the dark — but it is far below the edge
    float floorLum = 0.11 + 0.10 * staveEdge + 0.05 * parity;
    float wall = floorLum + edge * (0.60 + 0.40 * staveEdge);

    // the far end goes dark: without this the middle is a white pinprick and
    // the whole thing reads as a lamp, not as a hole
    float far = smoothstep(0.02, 0.26, r);
    // and the mouth falls off at the corners, so the walls do not end in a flat
    // wash against the edge of the tube
    float vig = 1.0 - 0.22 * smoothstep(0.50, 0.95, r);

    // the ring the beat lit up, on its way out
    float pd = depth - pulseDepth;
    float pulse = pulseAmt * exp(-pd * pd * 2.0);

    float lum = wall * far * vig * (0.42 + 0.62 * level) + pulse * far * 0.85;

    vec3 col = mix(ink, hot,
                   clamp(edge * 0.70 + parity * 0.12 + pulse, 0.0, 1.0)) * lum;
    float alpha = clamp(lum * 0.95 * dim, 0.0, 1.0);
    col = clamp(col * dim, 0.0, 1.6);
    fragColor = vec4(col * alpha, alpha) * qt_Opacity;   // premultiplied
}
