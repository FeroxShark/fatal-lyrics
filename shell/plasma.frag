#version 440
// fatal-lyrics — the plasma tube.
//
// Six blobs of light inside the glass, joining and pulling apart. They are
// metaballs: each one is a field r²/d², the fields are ADDED and the surface is
// where the sum crosses the threshold. That is what makes two blobs MERGE when
// they come close instead of overlapping, and what gives a NECK when they pull
// apart — a lamp made of circles looks like circles, a lamp made of fields
// looks like a liquid that splits.
//
// TANDA 4b: the blobs no longer live in here as sines of the clock. They come
// in as six `vec4(x, y, radius, angle)` uniforms, positioned by a damped spring
// in `Plasma.qml` at 60 Hz. A sine has no inertia, so the old lamp could not be
// pushed apart by a kick and drift back together — which is exactly what it
// looked like: one oval, nearly still.
//
//   · x, y   in units of `rmin`, the SHORT half-axis of the glass, so a blob is
//            the same size on the landscape screens and on the portrait one.
//   · radius same units. A blob the QML does not use arrives with radius 0 and
//            weighs nothing — no branch, no variable loop bound (GLSL ES 100).
//   · angle  the direction the blob is being pushed away from the centre. The
//            stretch (`elong`, from the bass) goes ALONG it. It travels as an
//            angle and not as `normalize(xy)` because at rest every blob sits
//            on top of the centre and that normalize is a division by nothing.
//
// The rim wobbles on three slow harmonics of the angle around the centre: the
// threshold is what wobbles, not the geometry, so it costs one `atan` for the
// whole picture instead of one per blob. Its phase is ACCUMULATED in QML —
// `sin(t * freq)` with a clock in the thousands teleports when the drop changes
// `freq` (same trap as the tunnel).
//
// The colour is flat palette inside with a `hot` rim: the rim is what reads as
// glowing glass.
//
// Build:  qsb --glsl "100 es,120,150" -o plasma.frag.qsb plasma.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float level;    // overall volume: how bright the wax burns
    float elong;    // bass: how much each blob is stretched along its angle
    float wobA;     // how deep the rim ripples
    float wobP;     // and the phase of that ripple, accumulated in QML
    float dim;
    vec2 res;
    vec3 ink;
    vec3 hot;
    vec4 b0;
    vec4 b1;
    vec4 b2;
    vec4 b3;
    vec4 b4;
    vec4 b5;
};

// One blob's field at `q` (in rmin units). Stretched along its own angle and
// squeezed across it, so the bass makes drops that lean outwards without
// changing how much wax there is.
float blob(vec2 q, vec4 b, float s) {
    vec2 d = q - b.xy;
    vec2 u = vec2(cos(b.w), sin(b.w));
    float dpar = dot(d, u) / s;
    float dper = (d.x * u.y - d.y * u.x) * s;
    // r²/d² blows up at the centre of a blob: never divide by nothing
    return b.z * b.z / max(dpar * dpar + dper * dper, 0.0004);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float ar = res.x / max(res.y, 1.0);
    vec2 p = vec2((uv.x - 0.5) * ar, uv.y - 0.5);

    // SAFE AREA (T4.1). The glass is the frame minus 4 % of air, and every
    // distance inside is measured against IT.
    vec2 glass = vec2(0.46 * ar, 0.46);
    float rmin = min(glass.x, glass.y);
    vec2 q = p / rmin;

    float s = 1.0 + elong;
    float field = blob(q, b0, s) + blob(q, b1, s) + blob(q, b2, s)
                + blob(q, b3, s) + blob(q, b4, s) + blob(q, b5, s);

    // The oval of the glass. This — and not the clamp in QML — is what keeps
    // the wax inside the 92 %: the QML clamp bounds one blob, but the surface
    // of three blobs merged reaches further than any of them. It starts to bite
    // at 0.78 of the way out — wide, so a drop thrown against the wall is still
    // a drop and not a smudge. The EGG of the resting bubble comes from the
    // oval the clusters are laid out on (`axX`/`axY` in Plasma.qml), not from here.
    field *= smoothstep(1.0, 0.78, length(p / glass));

    // the rim ripples: three harmonics, none a multiple of another
    float a = atan(q.y, q.x + 1e-5);
    float thr = 1.0 + wobA * (0.50 * sin(2.0 * a + wobP)
                            + 0.33 * sin(3.0 * a - 0.7 * wobP + 1.1)
                            + 0.22 * sin(5.0 * a + 1.6 * wobP));

    float e = 0.11 * thr;
    float body = smoothstep(thr - e, thr + e, field);
    // the rim: bright right at the surface, plain palette deeper in
    float rim = smoothstep(thr - 0.06, thr + 0.10, field)
              * (1.0 - smoothstep(thr + 0.12, thr + 0.75, field));

    vec3 col = mix(ink, hot, clamp(rim, 0.0, 1.0)) * (0.80 + 0.40 * level);
    float al = clamp(body * 0.94 * dim, 0.0, 1.0);
    col = clamp(col * dim, 0.0, 1.6);
    fragColor = vec4(col * al, al) * qt_Opacity;   // premultiplied, Qt expects it
}
