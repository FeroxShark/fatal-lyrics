#version 440
// fatal-lyrics — the dunes.
//
// A real desert, not a field of dots (Ferox 2026-11-05: "no se entiende que son dunas"; the old
// version was a perspective lattice of grains, and what it read as was a lattice). What makes a dune
// read as a dune, in the order they matter:
//   · the CREST: a long, sinuous and SHARP line. Long slope on the windward side, short steep slip
//     face on the other (`profile`),
//   · the TERMINATOR: a low sun rakes across, one face lit and the other in shadow, with a hard edge
//     between them right on the crest,
//   · the wind RIPPLES on the lit face, near the eye,
//   · layers fading into haze, and a low sun to explain the light.
//
// The landscape is a fixed heightfield and the camera travels over it (`dune`), raymarched per
// pixel. The projection is the one it always had: a point at depth Z lands at x = X / Z,
// y = HORIZON + (camY - h) / Z, so the ray of a pixel is X = sx · Z, height = camY - dy · Z.
//
// The music enters as sand in the air:
//   · every beat throws a plume at a spot of the field (`jump1`, `jump2`) and a gust lifts the sand
//     off the crests,
//   · in a drop (`lift`) the whole desert blows: sheets of sand cross the picture and the sun burns
//     through them; `high` makes them shiver.
//
// WALL (docs/PARED.md): with `wcfg.x` set, the camera is ONE for the whole canvas — each screen
// draws its window of the same panorama (`view`), the horizon is a single line across the canvas
// (30 % down it) and the unit is `span`, not this screen's height. Alone it is what it was.
//
// Build:  qsb --glsl "100 es,120,150" -o dunes.frag.qsb dunes.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float t;        // seconds since the dunes appeared
    float seed;     // 0..1, re-rolled every time the motif shows up
    float level;    // overall volume
    float high;     // high band: how hard the hovering sand shivers
    float speed;    // section energy: how fast the camera drifts
    float lift;     // 0..1 drop: the sand rises and stays in the air
    float qual;     // crtQuality: grain spacing, so a slow screen draws fewer
    float dim;      // 1 = the dunes ARE the picture
    vec2 res;       // surface size in pixels
    vec4 jump1;     // footstep: camera-space x and z, start time, strength
    vec4 jump2;     // a second one, so two beats can overlap
    vec3 ink;       // grain colour
    vec3 hot;       // crest colour
    vec4 view;      // WALL: uv = view.xy + qt_TexCoord0 · view.zw, in units of `span` from the canvas centre
    vec4 wcfg;      // WALL: x = 1 on the wall, y = px per unit, z = top of the canvas in units
};

// --------------------------------------------------------------- the landscape
const float ZNEAR = 0.45;
const float ZFAR = 48.0;
const float HMAX = 1.45;    // no dune is taller than this: rays above it are sky, no march

float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// One dune seen across the wind: long windward slope, then the crest, then a short slip face.
// The phase is continuous everywhere and the profile is 0 at both ends, so nothing breaks at the
// wrap of `fract`.
float profile(float u) {
    float saw = fract(u);
    const float CREST = 0.70;
    float wind = saw / CREST;
    wind = wind * wind * (1.6 - 0.6 * wind);
    float slip = (1.0 - saw) / (1.0 - CREST) * 0.72;
    // a crest is sharp but not a knife: without this rounding the ray slips past the edge
    const float K = 0.05;
    float m = clamp(0.5 + 0.5 * (slip - wind) / K, 0.0, 1.0);
    return mix(slip, wind, m) - K * m * (1.0 - m);
}

// The heightfield. The domain warp is what bends the crests into long curves, and the height of
// each one varies along it, so a crest dies out and another one takes over, as they do.
float duneBig(vec2 p, vec2 o) {
    float warp = vnoise(p * 0.13 + o) * 3.4 + vnoise(p * 0.37 + o * 1.3) * 0.8;
    float amp = 0.34 + 0.85 * vnoise(p * 0.09 - o);
    return profile(p.x * 0.15 + p.y * 0.19 + warp * 0.55) * amp + vnoise(p * 0.06 + o) * 0.28 - 0.1;
}

float dune(vec2 p) {
    vec2 o = vec2(seed * 137.0, seed * 311.0);
    // the swell on top is soft on purpose: a second set of sharp crests zebra-striped every slope
    return duneBig(p, o) + vnoise(p * 0.55 + o * 2.1) * 0.11;
}

// Wind ripples: a bump only for the light, not for the march. Across the wind, a little wavy, and
// only worth computing near the eye (past that they would alias into shimmer).
float ripples(vec2 p) {
    float w = vnoise(p * 1.7) * 2.4 + vnoise(p * 0.5) * 3.0;
    return sin((p.x * 0.60 + p.y * 0.80) * 30.0 + w * 3.0);
}

// A plume of thrown sand, in screen units: rises and spreads while it fades.
float plume(vec2 s, vec4 j, float horizon, float camY) {
    float age = t - j.z;
    if (j.w < 0.001 || age < 0.0 || age > 2.2)
        return 0.0;
    float z = max(j.y, 0.6);
    vec2 c = vec2(j.x / z, horizon + camY * 0.72 / z - age * 0.14 / z);
    float r = (0.09 + age * 0.26) / z;
    vec2 d = (s - c) / vec2(r * 1.7, r);
    float blob = exp(-dot(d, d) * 1.1);
    if (blob < 0.004)
        return 0.0;
    // soft on purpose: a hard threshold on the noise leaves specks that read as dirt on the sand
    float n = vnoise(s * 11.0 * z + vec2(-t * 1.8, seed * 90.0)) * 0.65
            + vnoise(s * 27.0 * z + vec2(-t * 2.9, 4.0)) * 0.35;
    return blob * (0.35 + 0.65 * n) * j.w * (1.0 - age / 2.2);
}

void main() {
    bool wall = wcfg.x > 0.5;
    vec2 uv = qt_TexCoord0;
    float aspect = wall ? 1.0 : res.x / max(res.y, 1.0);
    float sx = (uv.x - 0.5) * aspect;
    float yy = uv.y;
    if (wall) {
        vec2 w = view.xy + uv * view.zw;
        sx = w.x;
        yy = w.y - wcfg.z;
    }
    // en la pantalla vertical el horizonte a 0.30 deja mucho cielo vacío
    float HORIZON = res.y > res.x ? 0.22 : 0.30;
    if (wall)
        HORIZON = 0.30 * -2.0 * wcfg.z;      // 30 % down the canvas, one line for every screen
    float dy = yy - HORIZON;
    vec2 scr = vec2(sx, yy);

    // The drift. `t` already carries the rhythm of the music (the motif integrates its clock); a
    // `t · speed` here would teleport the camera whenever `speed` changed. Three periods that do
    // not line up: the shot never repeats.
    float camX = t * 0.05 + sin(t * 0.031 + seed * 6.283) * 1.6;
    float camZ = t * 0.34;
    float camY = 1.62 + 0.14 * sin(t * 0.043 + seed * 3.1);

    // The sun: low, off to one side (which one comes from the seed), so the light rakes across the
    // crests. Where it hangs on the sky and where the light comes from are the same direction.
    float side = fract(seed * 3.7) < 0.5 ? -1.0 : 1.0;
    vec2 sunS = vec2(side * 0.36 * max(aspect, 0.6), HORIZON - 0.115);
    vec3 sun = normalize(vec3(sunS.x, HORIZON - sunS.y, 1.0));
    sun = normalize(vec3(sun.x * 2.4, sun.y * 2.0, sun.z * 0.7));

    float gust = 0.0;
    float ga = t - jump1.z;
    if (ga >= 0.0 && ga < 1.4) gust += jump1.w * exp(-ga * 2.6);
    ga = t - jump2.z;
    if (ga >= 0.0 && ga < 1.4) gust += jump2.w * exp(-ga * 2.6);

    // ------------------------------------------------------------- the sky
    float up = clamp(-dy / max(HORIZON, 0.05), 0.0, 1.0);
    vec3 hazeCol = mix(ink, hot, 0.22) * (0.60 + 0.16 * level);
    vec3 col = mix(hazeCol, ink * 0.10, smoothstep(0.0, 0.75, up));
    float a = mix(0.92, 0.10, smoothstep(0.0, 0.9, up));
    // the disc and its glow; the drop burns through the blowing sand
    float sd = distance(scr, sunS);
    float disc = smoothstep(0.052, 0.047, sd);
    float glow = exp(-sd * 7.5) * (0.55 + 0.45 * lift) + exp(-sd * 2.2) * 0.14;
    col += hot * glow;
    a = max(a, clamp(glow * 1.2, 0.0, 1.0));
    col = mix(col, hot * 1.15, disc);
    a = max(a, disc);

    // ------------------------------------------------------------- the march
    float q = clamp(qual, 0.45, 1.0);
    float Z = ZNEAR;
    float hitZ = -1.0;
    vec2 seedO = vec2(seed * 137.0, seed * 311.0);
    // The march only needs the big shape: the small dunes are a fixed bound on top of it (0.11),
    // and the exact surface comes out of the bisection. Half the noise per step.
    if (camY - dy * ZNEAR < HMAX || dy > 0.0) {
        float prev = Z;
        for (int i = 0; i < 110; i++) {
            float ray = camY - dy * Z;
            if (ray > HMAX && dy < 0.0)
                break;
            float gap = ray - duneBig(vec2(sx * Z + camX, Z + camZ), seedO) - 0.11;
            if (gap < 0.0 || i == 109) {
                // the bound can fire above the real surface: walk on from here, on the real thing
                float lo = prev, hi = Z, zz = Z;
                bool found = false;
                for (int k = 0; k < 14; k++) {
                    if (camY - dy * zz - dune(vec2(sx * zz + camX, zz + camZ)) < 0.0) {
                        hi = zz; found = true;
                        break;
                    }
                    lo = zz;
                    zz += 0.018 * zz + 0.01;
                }
                if (found) {
                    for (int k = 0; k < 6; k++) {
                        float m = (lo + hi) * 0.5;
                        if (camY - dy * m - dune(vec2(sx * m + camX, m + camZ)) < 0.0)
                            hi = m;
                        else
                            lo = m;
                    }
                    hitZ = hi;
                    break;
                }
                prev = zz;
                Z = zz;
                continue;
            }
            prev = Z;
            Z += max(0.007 * Z / q, gap * 0.5);
            if (Z > ZFAR)
                break;
        }
    }

    // ------------------------------------------------------------- the sand
    if (hitZ > 0.0) {
        vec2 wp = vec2(sx * hitZ + camX, hitZ + camZ);
        float e = 0.012 + hitZ * 0.0016;
        float h0 = dune(wp);
        vec3 nrm = normalize(vec3(h0 - dune(wp + vec2(e, 0.0)), e, h0 - dune(wp + vec2(0.0, e))));
        // the terminator comes from the big shape: with the ripples in it, it frays into claw marks
        float lamb = dot(nrm, sun);
        float lit = smoothstep(0.015, 0.11, lamb);
        float near = smoothstep(15.0, 3.0, hitZ);
        float rip = 0.0;
        if (near > 0.0 && lit > 0.0) {
            float e2 = 0.006;
            float r0 = ripples(wp);
            vec2 rg = vec2(ripples(wp + vec2(e2, 0.0)) - r0, ripples(wp + vec2(0.0, e2)) - r0) / e2;
            rip = dot(vec3(-rg.x, 0.0, -rg.y), sun) * 0.0062 * near;
        }
        float l = lit * (0.42 + 0.78 * clamp((lamb + rip) * 1.25, 0.0, 1.0));
        // the shadow side is not black: it gets the sky, more when it faces up
        float sky = 0.085 + 0.09 * nrm.y;
        // the sand is not one colour: slow blotches, darker in the wind shadows
        float tone = 0.88 + 0.24 * vnoise(wp * 0.7 + seedO);
        vec3 c = ink * (sky + l * 0.90 * tone) + hot * pow(max(l, 0.0), 3.0) * 0.42;
        // grains catching the sun, right under the eye: one pixel, never a square
        float sp = hash21(floor(wp * 900.0));
        c += hot * step(0.997, sp) * near * near * lit * (0.15 + 0.45 * high);
        // the air: far away everything goes to the colour of the haze
        float fog = 1.0 - exp(-hitZ * hitZ * 0.0030 - hitZ * 0.006);
        col = mix(c, hazeCol, fog);
        a = 1.0;

        // sand streaming off the crests, downwind. Only where the slope flips, the crest line
        float crestiness = smoothstep(0.86, 0.6, nrm.y) * (1.0 - lit) * (1.0 - fog);
        float stream = vnoise(vec2(wp.x * 9.0 - t * 3.6, wp.y * 2.2 + t));
        col += mix(ink, hot, 0.4) * crestiness * smoothstep(0.5, 0.9, stream) * (0.9 * gust + 0.6 * lift);
    }

    // ------------------------------------------------------------- the air
    float puff = plume(scr, jump1, HORIZON, camY) + plume(scr, jump2, HORIZON, camY);
    if (puff > 0.0) {
        col = mix(col, mix(ink, hot, 0.35) * (0.85 + 0.3 * level), clamp(puff * 0.8, 0.0, 0.7));
        a = max(a, clamp(puff, 0.0, 1.0));
    }
    // the drop: sheets of sand cross the whole picture, low over the ground
    float low = smoothstep(-0.10, 0.20, dy);
    float blow = lift * 0.34 + gust * 0.05 + (speed - 1.0) * 0.015;
    if (blow > 0.004) {
        float shiver = sin(t * 38.0 + yy * 90.0) * 0.003 * (0.4 + high);
        // long thin streaks bent by a slow wave: a straight lattice of noise reads as bricks
        float bend = yy + vnoise(vec2(sx * 2.2 - t * 0.5, yy * 3.0)) * 0.09;
        float x = sx + shiver;
        float thin = vnoise(vec2(x * 1.3 - t * 2.2, bend * 120.0)) * 0.6
                   + vnoise(vec2(x * 2.9 - t * 3.1, bend * 260.0)) * 0.4;
        float mass = vnoise(vec2(x * 1.1 - t * 0.9, bend * 7.0));
        float amt = clamp(smoothstep(0.25, 0.85, thin) * smoothstep(0.2, 0.75, mass) * blow * low * 2.2, 0.0, 0.6);
        col = mix(col, mix(ink, hot, 0.3), amt);
        a = max(a, amt);
    }

    a = clamp(a * dim, 0.0, 1.0);
    col = clamp(col * dim, 0.0, 1.6);
    fragColor = vec4(col * a, a) * qt_Opacity;   // premultiplied, Qt expects it
}
