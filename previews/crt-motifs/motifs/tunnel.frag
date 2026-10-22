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
// The music: `level` is how hot the wall burns, `twist` wrings the bricks
// around the axis — and the wring grows with depth, so the far end of the
// tunnel is turned further round than the mouth. What the music does NOT do is
// change the speed: that is the drop and nothing else (see THE DROP below).
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
// LIGHT AND FOG (T5.3). What tells you a tunnel is deep is not the rings, it is
// that the far end goes DARK: `fog` is a plain exponential in depth, so the far
// end reaches the background and stays there, and the mouth gets a light of its
// own so the near wall is the brightest thing on screen. Before this the middle
// of the picture was the brightest part and it read as a lamp shade.
//
// THE DROP (T5.4). Outside a drop the tunnel travels at a CONSTANT speed — the
// uniform drift the reference video is built on — and the drop is the one thing
// that changes it: it speeds up and the wall smears in the direction of travel.
//
// And one light RUNS: on every beat a band of brightness is planted at the mouth
// and pushed down the wall away from the camera (QML moves `lightDepth`), which
// is the only thing here that says which way you are travelling. It replaced the
// ring the kick used to plant — a hoop flying at you and a light running away
// from you, both on the same beat, read as a fault and not as a pulse.
//
// DETAIL AND FILTERING (tanda 9: "mucho más detallado"). The wall used to be one
// flat tone per brick with a fixed-width smoothstep for every edge, and the
// brickwork faded out at a fixed depth to hide the aliasing. Now:
//   · every edge is filtered by the REAL pixel footprint (`fpV`, `fpU`: how much
//     of the brick one pixel covers, from `dz` and the screen size), so a joint
//     is a box-filtered line at any distance instead of a crawling one, and
//     each detail layer fades out on its own once it is smaller than a pixel —
//     the brick lives out to depth ~30 where it used to die at 15,
//   · each brick is a chamfered slab: a profile of distance-to-edge gives a
//     joint, a bevel and a flat face. The bevel is lit like a surface (the
//     camera lamp from the near side of each course, a second light from a
//     fixed screen corner against the brick's angular side), and the joint has
//     ambient occlusion. Every 4th course is a rib: wider bevel, brighter,
//   · inside the face: an inset panel line, four rivets, grain and vertical
//     scuffs (value noise in brick units, so it travels with the wall), and
//     about one brick in thirty is a lamp: its panel glows `hot`,
//   · a faint haze toward the far end and an interleaved-gradient dither at the
//     end, because the dark gradients are where an 8-bit pipeline bands.
// Precision: the course index and its fraction are kept apart (`ti`, `tf`) so
// the pattern does not shimmer after hours of uptime, when `t` is thousands.
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
    float blur;     // 0..1: the drop smear, along the direction of travel
    float lightDepth; // where the running light is now, in depth
    float lightAmt;   // 1 when it is planted, decaying as it runs
    float dim;
    vec2 res;
    vec3 ink;
    vec3 hot;
    vec4 win;       // WALL: this screen's window on the shared canvas, px (no wall: 0, 0, res)
    vec2 foc;       // WALL: the vanishing point, canvas px (no wall: the middle of the screen)
    float spn;      // WALL: the short side that measures the rings (no wall: min(res))
};

// Past this depth the bend stops winding: beyond it the whole far end shares
// ONE axis offset. Without the cap the phase winds infinitely fast as `dz` goes
// to infinity and the middle of the picture turns to noise.
const float ZCAP = 12.0;

// bricks in a turn, and the brick's world proportions: the tube has radius 2
// (that is what `dz = 2 / r` means), so a brick is 2π·2/12 wide and 1 deep. The
// 12 has to stay an integer (see the seam note in `wallAt`).
const float BRICKS = 12.0;
const float BW = 6.2831853 * 2.0 / BRICKS;

// hash without `sin`: the argument stays small, so it does not degrade with the
// course index. Only has to look uneven.
float h21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x),
               mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// a filtered step: 0 below `e - w`, 1 above `e + w`, linear-ish between. `w` is
// the pixel footprint, which is what makes the edge antialiased.
float fstep(float e, float w, float x) {
    return smoothstep(e - w, e + w, x);
}

// The wall at a point. `x` is depth past the nearest course boundary (its
// fraction `tf` already added, `ti` kept apart), `a` the turn, `wp` the pixel
// footprint in world units (a brick is 1 deep), `tl` how far this side of the
// tube faces the corner light. Returns
//   .x  surface luminance          .y  how much of it is hot (glints)
//   .z  lamp emission
// It is a function because the drop samples it twice. `soft` widens every edge
// (the smear); outside the drop it is 0.
vec3 wallAt(float x, float ti, float a, float wp, float tl, float soft, float sd) {
    float cf = floor(x);
    float v = x - cf;
    float course = cf + ti;
    float cm = mod(course, 1024.0);
    // running bond: half a brick of offset on every other course
    float ab = a * BRICKS + 0.5 * mod(course, 2.0);
    // The index is taken MOD the bricks in a turn. `ang` comes out of `atan`,
    // which wraps from +0.5 to -0.5 turns along the negative x axis: `ab` jumps
    // by exactly 12 there, and `fract(ab)` does not notice, but a bare
    // `floor(ab)` does — the brick straddling the cut got two different
    // indices, so two different tones, and the wall showed a horizontal seam
    // at mid-height on the left (tanda 8). 12 has to stay an integer (and the
    // same one as in `a * 12.0`) or the seam comes back.
    float fb = floor(ab);
    float brick = mod(fb, BRICKS);
    float u = ab - fb;
    float hb = h21(vec2(brick, cm) + sd);

    float w = wp + 0.5 * soft;                  // the filter width, world units
    float rib = step(mod(course, 4.0), 0.5);    // every 4th course is a rib

    // distance to the nearest side of the slab, in world units: a profile of
    // joint (dark) / bevel (lit) / face
    float du = min(u, 1.0 - u) * BW;
    float dv = min(v, 1.0 - v);
    float dE = min(du, dv);
    float g = 0.035 + 0.012 * rib;              // half-joint
    float bw = 0.085 + 0.075 * rib;             // bevel width
    float joint = 1.0 - fstep(g, w, dE);
    float bev = fstep(g, w, dE) * (1.0 - fstep(g + bw, w, dE));

    // which way the bevel faces. Near side of the course (v small) looks at the
    // camera lamp; the angular sides catch the corner light by how the wall at
    // this angle is turned toward it. Sign flips at the middle of the brick, so
    // `fstep` there is just a way to keep it continuous across the face.
    float sv = 1.0 - 2.0 * fstep(0.5, w, v);            // +1 near side, -1 far
    float su = 2.0 * fstep(0.5, w / BW, u) - 1.0;       // +1 / -1 angular sides
    float side = (dv < du) ? sv : su * tl;              // sign of the face we are on
    float lit = 1.0 + bev * (dv < du ? 0.85 * sv : 0.95 * side);

    // ambient occlusion in the creases: the face darkens as it nears a joint
    float ao = mix(0.62, 1.0, smoothstep(g, g + 0.30, dE));

    // brick tone, then everything that lives on the face
    float tone = 0.25 + 0.18 * hb;
    float lod = 1.0 - smoothstep(0.10, 0.34, w);        // sub-pixel stuff leaves
    // grain: two octaves, in brick units so it travels with the wall
    vec2 gp = vec2(ab * BW, x + ti);
    float gr = vnoise(gp * 7.0 + hb * 40.0) * 0.6 + vnoise(gp * 19.0 + 3.7) * 0.4;
    // vertical scuffs: stretched along the tube, a mean of 0 over the brick
    float sc = vnoise(vec2(ab * BW * 5.0 + hb * 17.0, (x + ti) * 0.55));
    tone *= 1.0 + lod * (0.26 * (gr - 0.5) + 0.34 * (sc - 0.5) * (1.0 - rib));

    // inset panel line on the face, and four rivets at its corners
    float inset = g + bw + 0.085;
    float pl = 1.0 - smoothstep(0.0, 0.012 + w, abs(dE - inset));
    pl *= (1.0 - rib) * step(inset, min(du, dv) + 0.5) * lod;
    vec2 q4 = vec2(abs(u - 0.5) * BW, abs(v - 0.5));
    vec2 rc = vec2(0.5 * BW - 0.21, 0.5 - 0.20);
    vec2 rd = q4 - rc;
    float rr = length(rd);
    float rivet = (1.0 - fstep(0.042, w, rr)) * (1.0 - rib) * (1.0 - smoothstep(0.012, 0.045, w));
    // the rivet is a dome: lit on the side that faces the light
    float dome = clamp(0.55 + 0.9 * dot(rd / max(rr, 0.001), vec2(-0.55 * tl, -0.8)), 0.0, 1.4);

    // lamps: one brick in thirty glows inside its panel
    float lampBrick = step(0.965, hb);
    float lamp = lampBrick * (1.0 - rib) * fstep(inset - 0.02, w, min(du, dv));

    float lum = tone * lit * ao * mix(0.35, 1.0, 1.0 - joint);
    lum *= 1.0 - 0.30 * pl;
    lum += rivet * (0.10 + 0.28 * dome);
    // a rib is a raised band: brighter, and its bevel catches the lamp
    lum *= 1.0 + 0.30 * rib;

    float hot = bev * (dv < du ? max(sv, 0.0) : 0.25 * max(side, 0.0)) * (0.55 + 0.45 * rib)
              + rivet * 0.30 * dome;

    // far away the structure averages out instead of going to noise
    float mean = 0.27 * (1.0 + 0.30 * rib) * 0.80;
    float keep = 1.0 - smoothstep(0.35, 0.95, w);
    return vec3(mix(mean, lum, keep), hot * keep, lamp * keep);
}

// interleaved gradient noise: a cheap, even dither with no visible pattern
float ign(vec2 p) {
    return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void main() {
    // normalised by the SHORT side: the short edge runs -0.5..0.5 and the long
    // one overflows, so the same ring is the same size on every screen.
    // WALL (docs/PARED.md): the point is read off the shared canvas and the vanishing
    // point is the focus (the screen with the lyric), so the screens are one tunnel seen
    // from the inside. On one screen win = (0, 0, res), foc = res / 2, spn = min(res):
    // exactly (uv - 0.5) * res / min(res).
    float spnx = max(spn, 1.0);
    vec2 q = (win.xy + qt_TexCoord0 * win.zw - foc) / spnx;
    // one pixel, in q units (1 / min(res) on one screen)
    float pxq = win.z / max(res.x, 1.0) / spnx;

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
    // `t` split in integer and fraction: the pattern is a function of the course
    // number (integer, exact) and the fraction (small), never of one big float
    float ti = floor(t);
    float x = dz + (t - ti);
    float depth = dz + t;               // only for the running light
    // the wring grows with depth: the far end turns more than the mouth. It
    // rides on `dz` and NOT on `depth`, which carries `t`: `t` is hundreds by
    // then, so a change of pitch would multiply it and spin every ring at once.
    float a = ang + roll + twist * dz * 0.03;

    // The pixel footprint in world units (a brick is 1 deep, BW wide): radially
    // one pixel is `dz²/2` of a course over the short side, round the tube it is
    // `dz` of a brick width. The larger of the two is the filter.
    float fpR = dz * dz * 0.5 * pxq;
    float fpC = dz * pxq;
    float wp = max(fpR, fpC);
    // the corner light: which way this side of the wall turns toward the top
    // left of the screen. The tangent is perpendicular to the radius.
    float tl = clamp(dot(vec2(-sin(ang * 6.283185), cos(ang * 6.283185)), vec2(-0.6, 0.8)) * 1.6, -1.0, 1.0);

    // THE DROP (T5.4): the tube speeds up and the wall SMEARS along the way it
    // is travelling. Two samples a fraction of a course apart, averaged, plus
    // every edge widened: what was one course of bricks becomes two ghosts of
    // it, which is a smear in depth and reads as radial on screen. Two samples
    // and not a loop — one evaluation per pixel is the budget, and outside the
    // drop the second one lands on the same place and costs the same.
    float soft = 0.11 * blur;
    float sd = seed * 31.7;
    vec3 w0 = wallAt(x, ti, a, wp, tl, soft, sd);
    vec3 w1 = (blur > 0.002) ? wallAt(x - 0.55 * blur, ti, a, wp, tl, soft, sd) : w0;
    vec3 wl = mix(w0, w1, 0.45 * blur);
    float wall = wl.x;

    // The far end goes dark, and it gets there smoothly: an exponential has no
    // knee, so there is no ring where "the fog starts". It is measured from the
    // nearest thing on screen (the corners, at depth 2), so the mouth is not
    // already dimmed before anything has happened.
    float za = max(dz - 2.0, 0.0);
    float fog = exp(-za * 0.125);
    // and the mouth has a light of its own: the near wall is the brightest
    // thing in the picture, which is what says the hole goes AWAY
    float mouth = 1.0 + 0.75 * exp(-za * 0.45);
    // the corners still fall off, so the wall does not end in a flat wash
    // against the edge of the tube
    float vig = 1.0 - 0.20 * smoothstep(0.55, 1.05, r);

    // the light running down the wall. A BAND and not a ring: it has to read as
    // light falling on a surface, not as one more course of bricks.
    float ld = depth - lightDepth;
    float lite = lightAmt * exp(-ld * ld * 0.32);

    // The smear costs brightness by construction: averaging two samples halves
    // any highlight only one of them has, and measured, the drop came out
    // DARKER than the verse — which is backwards. The gain pays it back.
    float gain = (0.55 + 0.80 * level) * (1.0 + 0.75 * blur);
    // haze: the air in the tube scatters the lamp, so the far end is not a hole
    // cut in the screen but a faint glow you are flying into
    float haze = 0.075 * exp(-r * 6.0) * (0.6 + 0.8 * level);
    float lum = wall * fog * mouth * vig * gain
              + wl.z * 0.34 * fog * (0.7 + 0.5 * level)
              + lite * fog * 0.85
              + haze;

    // hot: the lit chamfers, the rivets, the lamps and the running light
    float hotw = clamp(wl.y * 0.9 + wl.z * 0.35 + lite, 0.0, 1.0);
    vec3 col = mix(ink, hot, hotw) * lum;
    // Alpha-composited like every other motif: what is far away has no
    // brightness, so it hands the picture back to the tube. Two things that do
    // NOT work were tried here and are worth not trying again: painting the far
    // end opaque black (`max(lum, 1 - fog)`) puts the black ON TOP of the
    // bricks, and at half a screen of depth that is a 50% wash over the only
    // texture this picture has — the wall went flat; and drawing the whole
    // thing near-opaque over a backdrop of its own kills the inverted palette
    // faces, where `ink` is dark and the tube bed is light, and the screen came
    // out an even dark slab.
    //
    // The price is that on those inverted faces the far end is the LIGHT of the
    // bed instead of black. That is the same deal every motif on this wall
    // takes, and it is in CHECKS-VISUALES to be looked at.
    float alpha = clamp(lum * 0.95 * dim, 0.0, 1.0);
    col = clamp(col * dim, 0.0, 1.6);
    vec3 pm = col * alpha;
    // dither: ±1/255 on the premultiplied result, kept under the alpha so it
    // never turns black bed into grey
    float dth = (ign(gl_FragCoord.xy) - 0.5) * (1.0 / 255.0);
    alpha = clamp(alpha + dth, 0.0, 1.0);
    pm = clamp(pm + dth * ink, vec3(0.0), vec3(alpha));
    fragColor = vec4(pm, alpha) * qt_Opacity;   // premultiplied
}
