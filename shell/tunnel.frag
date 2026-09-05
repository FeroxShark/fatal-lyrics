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
// FRAME (T5.1). Everything is measured against the SHORT SIDE of the screen
// (`min(w, h)`), so a ring is the same size on the portrait monitor and on the
// landscape ones. Before this the x was scaled by the aspect, which is
// normalising by the HEIGHT: on DP-4 (1080x1920) that made the mouth as wide as
// the screen is TALL, and the far end reached a corner radius of 0.57 where the
// landscape screens reached 1.02 — two different tunnels on the same wall.
//
// THE CURVE (T5.1). The tunnel BENDS: the axis of the tube walks sideways as
// it goes away, `C(z)`, so the far rings are off-centre and the mouth stays put
// — you are flying into a bend. The centre used to drift as one 2D offset for
// the whole picture, which moves the mouth as much as the far end and reads as
// the whole tube sliding sideways.
//
// The projection is what keeps it from tearing. A ring whose axis is `C` at
// distance `z` lands on screen offset by `C/z`, and its radius is `R/z` — so
// the offset is a FRACTION of that ring's own radius, and that fraction is
// `C/R`, which changes slowly. Written that way (`c = r · C(dz)/2`) the warp is
// injective for `|C| < 2` and the picture cannot fold.
//
// Written the obvious way (`c = A · w(dz)`, a plain offset in depth) it DOES
// fold, and it is worth knowing why: `d(dz)/dr = -dz²/2`, hundreds near the
// centre, and on top of that `|c|` stops being smaller than `r` — the first
// try at this drew claws and cusps over the middle rings. And solving
// `p = q - c(depth(p))` by iterating does not converge for the same reason.
//
// `C` is zero at the camera (the axis passes through the eye: the sines are
// written as differences so `C(0) = 0`), so the mouth never slides, and past
// `ZCAP` it freezes: further than that the phase would wind faster than the
// pixels and the middle of the picture would turn to noise.
//
// The music: `level` is how fast the rings arrive (up in QML), `twist` wrings
// them around the axis — and the wring grows with depth, so the far end of the
// tunnel turns more than the mouth.
//
// CONTRAST (T3.B8). The first version had a wide soft plateau per ring, and at
// any distance that reads as one gradient: Ferox saw "casi no hay contraste
// entre los anillos". Now a ring is a THIN hot edge over a near-black floor,
// there is a vignette so the mouth falls off at the corners as well as at the
// far end, and every kick plants a lit ring that flies out with the others.
//
// The pulse costs nothing to move: a constant value of `depth` travels outwards
// by itself, because `depth = 2/r + t` and `t` grows — so a ring planted at
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
    float ct;       // plain seconds: only the bend slither uses this
    float twist;    // -0.5..0.5, from pitch: the wring
    float seed;     // 0..1, re-rolled every appearance
    float level;    // overall volume: how hot the walls burn
    float bend;     // how hard the tunnel curves, in tube radii (< 1.8)
    float pulseDepth; // where the lit ring was planted, in depth
    float pulseAmt;   // 1 on a kick, decaying
    float dim;
    vec2 res;
    vec3 ink;
    vec3 hot;
};

// Past this depth the bend stops winding: beyond it the whole far end shares
// ONE axis offset. Without the cap the phase winds infinitely fast as `dz` goes
// to infinity and the middle of the picture turns to noise.
const float ZCAP = 12.0;

void main() {
    vec2 uv = qt_TexCoord0;
    // normalised by the SHORT side: the short edge runs -0.5..0.5 and the long
    // one overflows, so the same ring is the same size on every screen
    vec2 q = (uv - 0.5) * (res / max(min(res.x, res.y), 1.0));

    // 1/r is the depth. Never divide by nothing: at the exact centre that is a
    // NaN, and a NaN is a hole punched in the picture.
    float rq = max(length(q), 0.0015);
    float dzq = 2.0 / rq;               // depth ahead of the camera, unbent

    // Where the axis of the tube is at that depth, in tube radii. Two periods
    // that do not divide each other, so the bend never comes back to where it
    // was, and both written as a DIFFERENCE of sines so that `C(0) = 0`: the
    // axis goes through the camera, so the mouth cannot slide sideways.
    float zc = min(dzq, ZCAP) + t;
    float p1 = ct * 0.21 + seed * 6.283;
    float p2 = ct * 0.17 + seed * 4.11;
    vec2 axis = bend * vec2(sin(zc * 0.130 + p1) - sin(t * 0.130 + p1),
                            sin(zc * 0.098 + p2) - sin(t * 0.098 + p2));
    // and the projection: offset on screen = axis / distance = axis · r / 2
    vec2 p = q - rq * 0.5 * axis;

    float r = max(length(p), 0.0015);
    float ang = atan(p.y, p.x) / 6.283185;

    // The 2.0 sets how many rings fit on screen: with the old 0.42 there were
    // barely two and a half between the mouth and the far end, which with a
    // thin edge profile leaves a black field with a couple of hoops in it.
    float dz = 2.0 / r;
    float depth = dz + t;
    // the wring grows with depth: the far end turns more than the mouth. It
    // rides on `dz` and NOT on `depth`, which carries `t`: `t` is hundreds by
    // then, so a change of pitch would multiply it and spin every ring at once.
    float a = ang + twist * dz * 0.03;

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
