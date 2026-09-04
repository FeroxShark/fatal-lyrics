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
// The music: `level` is how fast the rings arrive (up in QML), `twist` wrings
// them around the axis — and the wring grows with depth, so the far end of the
// tunnel turns more than the mouth — and the centre drifts on its own slow
// clock, which is what keeps it from looking like a target painted on glass.
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
    float dim;
    vec2 res;
    vec3 ink;
    vec3 hot;
};

void main() {
    vec2 uv = qt_TexCoord0;
    float ar = res.x / max(res.y, 1.0);

    // the mouth wanders: three periods that do not divide each other, so it
    // never comes back to where it was
    vec2 centre = vec2(0.08 * sin(ct * 0.13 + seed * 6.283),
                       0.06 * cos(ct * 0.091 + seed * 4.11));
    vec2 p = vec2((uv.x - 0.5) * ar, uv.y - 0.5) - centre;

    // 1/r is the depth. Never divide by nothing: at the exact centre that is a
    // NaN, and a NaN is a hole punched in the picture.
    float r = max(length(p), 0.0015);
    float ang = atan(p.y, p.x) / 6.283185;

    float depth = 0.42 / r + t;
    // the wring grows with depth: the far end turns more than the mouth
    float a = ang + twist * depth * 0.11;

    // the rings, and the staves running along the walls
    float ring = fract(depth);
    float ringEdge = smoothstep(0.0, 0.10, ring) * (1.0 - smoothstep(0.62, 0.96, ring));
    float stave = fract(a * 10.0);
    float staveEdge = smoothstep(0.0, 0.12, stave) * (1.0 - smoothstep(0.70, 1.0, stave));

    // brick parity: alternate the tone ring by ring, so the walls have a grain
    float parity = mod(floor(depth) + floor(a * 10.0), 2.0);

    float wall = clamp(ringEdge * (0.45 + 0.55 * staveEdge), 0.0, 1.0);

    // the far end goes dark: without this the middle is a white pinprick and
    // the whole thing reads as a lamp, not as a hole
    float far = smoothstep(0.02, 0.26, r);
    float lum = wall * far * (0.45 + 0.60 * level);

    vec3 col = mix(ink, hot, parity * 0.55 + 0.20 * staveEdge) * lum;
    float alpha = clamp(lum * 0.95 * dim, 0.0, 1.0);
    col = clamp(col * dim, 0.0, 1.6);
    fragColor = vec4(col * alpha, alpha) * qt_Opacity;   // premultiplied
}
