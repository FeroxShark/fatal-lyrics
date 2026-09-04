#version 440
// fatal-lyrics — the dunes.
//
// A desert of loose grains seen from just above the sand, built on the same
// idea as `ocean.frag`: no mesh, every grain is its own point, projected by
// hand with a perspective divide, and its height solved analytically. What
// changes is what the height means — here it is a landscape that does NOT
// move on its own. The dunes are a fixed heightmap; what moves is the camera.
//
// Two things make it never look like the same shot twice:
//   · `seed` re-rolls the noise offsets on every appearance, so the ridges are
//     somewhere else,
//   · the camera pans, creeps forward and rises a little, all on periods that
//     do not divide each other, so it never comes back to a frame it already
//     showed.
//
// The music enters as sand in the air, never as a colour flash:
//   · every beat drops a giant footstep at a random spot and the grains around
//     it are thrown up, fall under gravity and bounce once, small,
//   · in a drop the whole field lifts and HOVERS, jittering a pixel or two at
//     high frequency, and comes down together when the drop ends.
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
};

// --------------------------------------------------------------- the camera
// Eye `camY` above the sand looking flat along it. A grain at (X, h, Z) in
// camera space lands at screen y = HORIZON + (camY - h) / Z, x = X / Z.
const float HORIZON = 0.30;
const float Z0 = 1.30;    // first row of grains still on screen
const float GRAINR = 0.020;
const float GRAV = 3.2;   // how fast a thrown grain comes back down
const float BOUNCE = 0.42;

float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// value noise, smooth enough that the dunes read as sand and not as facets
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

// The landscape. Three octaves is where a ridge stops looking like a bump and
// starts looking like a dune with a windward side; a fourth costs the same as
// the whole projection and nobody sees it at this dot density.
float dune(vec2 p) {
    vec2 o = vec2(seed * 137.0, seed * 311.0);
    float h = vnoise(p * 0.45 + o) * 0.62;
    h += vnoise(p * 1.10 + o * 1.7) * 0.26;
    h += vnoise(p * 2.60 + o * 2.9) * 0.12;
    return (h - 0.5) * 0.34;
}

// A giant footstep: the grains near it are thrown up, fall, and bounce once.
// The falloff is what makes it a footstep and not the whole desert jumping.
// `p` here is the grain in CAMERA space — see the call site.
float footstep(vec2 p, vec4 j) {
    float age = t - j.z;
    if (j.w < 0.001 || age < 0.0 || age > 3.0)
        return 0.0;
    float d = distance(p, j.xy);
    float near = exp(-d * d * 0.55);
    if (near < 0.01)
        return 0.0;
    float v0 = (0.42 + 0.5 * level) * j.w * near;
    float flight = 2.0 * v0 / GRAV;
    if (age < flight)
        return v0 * age - 0.5 * GRAV * age * age;
    float v1 = v0 * BOUNCE;
    float a2 = age - flight;
    float flight2 = 2.0 * v1 / GRAV;
    if (a2 < flight2)
        return v1 * a2 - 0.5 * GRAV * a2 * a2;
    return 0.0;
}

void main() {
    vec2 uv = qt_TexCoord0;
    float aspect = res.x / max(res.y, 1.0);
    float sx = (uv.x - 0.5) * aspect;
    float dy = uv.y - HORIZON;

    // The drift. Three periods that do not line up: the shot never repeats.
    float tt = t * max(speed, 0.35);
    float camX = tt * 0.045 + sin(tt * 0.031 + seed * 6.283) * 1.6;
    float camZ = tt * 0.075;
    float camY = 1.0 + 0.16 * sin(tt * 0.021 + seed * 3.1);

    // grain spacing: fewer, bigger grains on a screen that cannot afford them
    float q = clamp(qual, 0.45, 1.0);
    float DZ = 0.135 / q;
    float DX = 0.165 / q;

    vec3 col = vec3(0.0);
    float a = 0.0;

    // the far edge. Darker than the grains on purpose: the horizon of a desert
    // is where the sand runs out of light, not a lit stripe like the sea's.
    float glow = exp(-abs(dy) * 55.0) * 0.22 + exp(-abs(dy) * 9.0) * 0.07;
    col += mix(ink, vec3(0.0), 0.45) * glow * (0.6 + 0.5 * level);
    a = max(a, glow * 0.6);

    if (dy > 0.0008) {
        float drift = fract(camZ / DZ) * DZ;
        float z = camY / dy;              // depth of flat sand under this pixel
        float jf = (z - Z0 + drift) / DZ;
        float worldX = sx * z;
        int j0 = int(floor(jf));

        for (int dj = -2; dj <= 2; dj++) {
            // low quality also looks at fewer neighbouring rows: the far ones
            // are the expensive half and the ones nobody can resolve
            if (q < 0.8 && (dj < -1 || dj > 1))
                continue;
            int j = j0 + dj;
            if (j < 0)
                continue;
            float Z = Z0 + float(j) * DZ - drift;
            if (Z < 0.55)
                continue;

            float stagger = mod(float(j), 2.0) * 0.5;
            float ifl = worldX / DX - stagger;
            int i0 = int(floor(ifl));

            float rad = clamp(GRAINR / Z * res.y, 0.8, res.y * 0.010);

            for (int di = -1; di <= 1; di++) {
                int i = i0 + di;
                float X = (float(i) + stagger) * DX;
                float px = X / Z;
                float dx = (sx - px) * res.y;
                if (abs(dx) > rad + 1.0)
                    continue;

                // world position of this grain: the lattice is in CAMERA space
                // and the landscape is not, so the camera offset goes in here.
                // Without it the dunes would travel with the eye and nothing
                // would ever come closer.
                vec2 wp = vec2(X + camX, Z + camZ);
                float own = hash21(vec2(float(i), float(j)));
                float h = dune(wp);
                // The footstep is measured in CAMERA space, not world space:
                // it lasts three seconds and has to stay where it landed on
                // screen. In world space the pan would carry it off frame.
                h += footstep(vec2(X, Z), jump1) + footstep(vec2(X, Z), jump2);
                // the drop: the field hangs in the air, shivering. The shiver is
                // in world units, sized so it lands on one or two pixels at the
                // depth where most of the grains are.
                h += lift * (0.20 + 0.10 * own);
                h += lift * sin(t * 38.0 + own * 6.283) * 0.0035 * (0.4 + high);

                float py = HORIZON + (camY - h) / Z;
                vec2 d = vec2(dx, (uv.y - py) * res.y);
                float g = smoothstep(rad, rad * 0.3, length(d));
                if (g <= 0.001)
                    continue;

                float fade = exp(-(Z - Z0) * 0.13);
                // the ridge catches the light; the trough only dims. A grain
                // drawn darker than the sand reads as a hole in the picture.
                float crest = clamp(h * 6.0 + 0.5, 0.0, 1.0);
                vec3 c = mix(ink, hot, crest * crest);
                float bright = (0.42 + 0.8 * crest) * fade;

                col += c * g * bright;
                a = max(a, g * bright * 0.92);
            }
        }
    }

    a = clamp(a * dim, 0.0, 1.0);
    col = clamp(col * dim, 0.0, 1.6);
    fragColor = vec4(col * a, a) * qt_Opacity;   // premultiplied, Qt expects it
}
