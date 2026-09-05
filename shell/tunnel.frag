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
// entre los anillos". A ring is a THIN hot edge over a dark floor.
//
// THE WALL (T5.2). Concentric rings on a flat floor are hoops, not a tunnel:
// there is nothing to tell you the wall is a surface. So the wall is laid in
// VOUSSOIRS at two scales — a course of bricks per ring, offset by half a brick
// every other course (running bond, which is what stops the joints from lining
// up into radial spokes), and three hairline sub-joints inside each brick — and
// every brick gets its own tone out of a hash of (course, brick), so no two are
// the same. The bricks turn with the tube: `roll` is an accumulated angle from
// QML (never `clock × speed`, which teleports on any change of rate) and the
// torsion adds to it with depth, so the far end is wrung further round than the
// mouth.
//
// The detail FADES with distance (`detail`), and that is not decoration: past
// about twelve deep, one brick is thinner than a pixel and the texture turns
// into crawling noise. What is left there is the plain course edge.
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
    float roll;     // accumulated barrel rotation, in turns (from QML)
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

// one number per brick: a hash of (course, brick). `sin` of a big argument is
// the cheapest hash there is and this one only has to look uneven.
float brickTone(vec2 v) {
    return fract(sin(dot(v, vec2(127.1, 311.7))) * 43758.5453);
}

// The wall at a depth and an angle. It is a function because the drop samples
// it twice; outside the drop the second sample lands on the same place.
// `soft` widens every edge (the smear), `detail` fades the brickwork out with
// distance so it does not alias into noise.
float wallAt(float depth, float a, float detail, float soft, float sd) {
    float course = floor(depth);
    float v = fract(depth);
    // running bond: half a brick of offset on every other course
    float ab = a * 12.0 + 0.5 * mod(course, 2.0);
    float brick = floor(ab);
    float u = fract(ab);

    // the joint around each brick: dark mortar, the brick face inside it
    float face = smoothstep(0.0, 0.045 + soft, u) * (1.0 - smoothstep(0.955 - soft, 1.0, u))
               * smoothstep(0.0, 0.075 + soft, v) * (1.0 - smoothstep(0.925 - soft, 1.0, v));
    // and three hairlines inside the brick, so the scale reads at the mouth too
    float fine = fract(ab * 3.0);
    float hair = 1.0 - 0.22 * detail * (1.0 - smoothstep(0.0, 0.05 + soft, fine));

    // Every brick its own tone. `detail` does not switch the texture off, it
    // FLATTENS it: far away every brick is worth the average and the wall is
    // one even tone, instead of going dark and leaving a hole in the picture.
    float lum = 0.20 + 0.17 * brickTone(vec2(brick, course) + sd);
    lum = mix(lum, mix(0.045, lum, face), detail) * hair;

    // the near edge of the course lights up: THAT is what reads as a ring, and
    // it is even all the way round — modulated by the brick it turned into a
    // ring of bright dashes and the wall read as a machine, not as masonry
    float d0 = abs(v - 0.5) * 2.0;
    return lum + smoothstep(0.74 - soft, 1.0, d0) * 0.40;
}

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
    float a = ang + roll + twist * dz * 0.03;

    // Past twelve deep a brick is thinner than a pixel: the brickwork fades out
    // and what is left is the course edge. Without this the middle of the
    // picture crawls.
    float detail = smoothstep(15.0, 5.0, dz);
    float wall = wallAt(depth, a, detail, 0.0, seed * 31.7);
    float d0 = abs(fract(depth) - 0.5) * 2.0;
    float edge = smoothstep(0.72, 1.0, d0);

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

    vec3 col = mix(ink, hot, clamp(edge * 0.70 + pulse, 0.0, 1.0)) * lum;
    float alpha = clamp(lum * 0.95 * dim, 0.0, 1.0);
    col = clamp(col * dim, 0.0, 1.6);
    fragColor = vec4(col * alpha, alpha) * qt_Opacity;   // premultiplied
}
