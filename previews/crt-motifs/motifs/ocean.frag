#version 440
// fatal-lyrics — the sea.
//
// A sea at night, not a sheet of dots (Ferox 2026-11-05: "no se entiende"). What reads as water:
//   · waves with sharp crests and wide troughs, many of them in different directions (`waves`),
//   · the sky mirrored on it, strong at a grazing angle and weak straight down (Fresnel), and that
//     is where the horizon comes from: nothing draws one,
//   · the moon's column of glitter, broken by every little facet,
//   · foam on the crests that are about to fall.
//
// The beat drops a stone: a ring crosses the water, each point rising when the front reaches IT.
// That delay by distance is what makes it physics and not a lamp; the ring also leaves foam.
//
// Same camera as ever: eye one unit above the water, a point at (X, h, Z) lands at x = X / Z,
// y = HORIZON + (1 - h) / Z. `t` already carries the rhythm of the music (never `t · speed`: it
// would teleport the sea whenever `speed` changes); `speed` is how rough it gets.
//
// Build:  qsb --glsl "100 es,120,150" -o ocean.frag.qsb ocean.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float t;        // seconds since the sea appeared
    float amp;      // wave height knob, 0..1
    float swell;    // low band: the long rollers
    float chop;     // high band: the fine ripple on top
    float level;    // overall volume, drives how alive the dots are
    float speed;    // section energy: quiet verse crawls, a drop runs
    float haze;     // how fast distance eats the dots
    float dim;      // 1 = the sea IS the picture, <1 = it sits behind the lyric
    vec2 res;       // surface size in pixels
    vec4 rip1;      // ring: world x, world z, start time, strength
    vec4 rip2;      // a second one, so two beats can be crossing at once
    vec3 ink;       // dot colour
    vec3 hot;       // crest colour
    vec4 view;      // WALL: uv = view.xy + qt_TexCoord0 · view.zw, in units of `span` from the canvas centre
    vec4 wcfg;      // WALL: x = 1 on the wall, y = px per unit, z = top of the canvas in units
};

// --------------------------------------------------------------- the water
const float HORIZON = 0.34;
const float RIPV = 2.4;    // how fast a ring crosses the water

float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// The ring of a stone: height and its pull on the slope, radial.
vec3 ring(vec2 p, vec4 r) {
    float age = t - r.z;
    if (r.w < 0.001 || age < 0.0 || age > 6.0)
        return vec3(0.0);
    vec2 v = p - r.xy;
    float dist = length(v);
    float d = dist - age * RIPV;
    float env = exp(-d * d * 1.6) * exp(-age * 0.85) * exp(-dist * 0.10) * r.w;
    return vec3(sin(d * 4.2) * env, (v / max(dist, 0.001)) * cos(d * 4.2) * 4.2 * env);
}

// The waves. Each one is exp(sin) - sharp crest, wide trough - and pushes the sample point along
// its slope before the next one reads it: that is what bunches the small waves on the big ones.
// `lod` drops the ones too small to see at this distance. Returns (height, d/dx, d/dz).
vec3 waves(vec2 p, int count, float lod) {
    float rough = 0.75 + 0.55 * clamp(speed, 0.0, 1.6) + 0.5 * swell;
    float freq = 0.85;
    float a = 0.115 * (0.55 + 0.75 * amp) * rough;
    float tw = t * 0.92;
    float ang = 0.6;
    vec3 sum = vec3(0.0);
    for (int i = 0; i < count; i++) {
        vec2 dir = vec2(sin(ang), cos(ang));
        float ph = dot(p, dir) * freq + tw * sqrt(freq) * 1.35;
        float w = exp(sin(ph) - 1.0);
        float slope = w * cos(ph);
        float keep = exp(-lod * freq * freq);
        sum += vec3(w * a, dir * slope * a * freq) * keep;
        p -= dir * slope * a * 0.55;
        freq *= 1.27;
        a *= 0.80 + 0.04 * chop;
        ang += 2.399;
    }
    return sum;
}

void main() {
    // WALL (docs/PARED.md): the camera is ONE for the whole canvas, each screen draws its window
    // of the same panorama and the horizon is a single line across it (34 % down). Alone: as ever.
    bool wall = wcfg.x > 0.5;
    vec2 uv = qt_TexCoord0;
    float aspect = res.x / max(res.y, 1.0);
    float sx = (uv.x - 0.5) * aspect;
    float yy = uv.y;
    float HZ = HORIZON;
    if (wall) {
        vec2 w = view.xy + uv * view.zw;
        sx = w.x;
        yy = w.y - wcfg.z;
        HZ = HORIZON * -2.0 * wcfg.z;
    }
    float dy = yy - HZ;
    vec2 scr = vec2(sx, yy);

    // the moon: straight ahead of the eye, so its column runs down the middle of the canvas
    // (on the wall not the screen's aspect: every window has to agree on where the moon is)
    vec2 moonS = vec2(sin(t * 0.009) * 0.08 * (wall ? 1.7 : aspect), HZ - 0.15);
    vec3 moon = normalize(vec3(moonS.x, HZ - moonS.y, 1.0));

    vec3 haze = mix(ink, hot, 0.25) * (0.50 + 0.14 * level);
    float up = clamp(-dy / max(HZ, 0.05), 0.0, 1.0);

    vec3 col;
    float a;
    if (dy <= 0.0015) {
        // ------------------------------------------------------------- the sky
        col = mix(haze, ink * 0.05, smoothstep(0.0, 0.8, up));
        a = mix(0.92, 0.08, smoothstep(0.0, 0.95, up));
        float md = distance(scr, moonS);
        float disc = smoothstep(0.044, 0.040, md);
        float glow = exp(-md * 8.5) * 0.55 + exp(-md * 2.4) * 0.10;
        // the disc's grey seas, so it is the moon and not a lamp
        float seas = vnoise((scr - moonS) * 42.0 + 3.0) * 0.6 + vnoise((scr - moonS) * 96.0) * 0.4;
        col += hot * glow;
        a = max(a, clamp(glow * 1.3, 0.0, 1.0));
        col = mix(col, hot * (0.82 + 0.34 * seas), disc);
        a = max(a, disc);
    } else {
        // ------------------------------------------------------------- the sea
        float Z = 1.0 / dy;
        Z = min(Z, 90.0);
        // the surface is not flat: walk the depth to where the ray meets it
        float lod = Z * Z * 0.00026;
        vec3 w0 = waves(vec2(sx * Z, Z), 7, lod);
        Z = (1.0 - w0.x) / dy;
        Z = clamp(Z, 0.5, 90.0);
        vec2 p = vec2(sx * Z, Z);

        vec3 w1 = waves(p, 20, lod);
        vec3 r1 = ring(p, rip1);
        vec3 r2 = ring(p, rip2);
        float rh = (r1.x + r2.x) * 0.20 * (0.4 + amp);
        vec2 grad = w1.yz + (r1.yz + r2.yz) * 0.20 * (0.4 + amp);
        vec3 n = normalize(vec3(-grad.x, 1.0, -grad.y));

        // looking along the ray; grazing near the horizon, so Fresnel is what lights the far water
        vec3 eye = normalize(vec3(sx, -dy, 1.0));
        vec3 refl = reflect(eye, n);
        float fres = 0.03 + 0.97 * pow(clamp(1.0 + dot(eye, n), 0.0, 1.0), 4.0);

        // what the water mirrors: the sky, lighter towards the horizon
        float skyUp = clamp(refl.y, 0.0, 1.0);
        vec3 skyRefl = mix(haze * 1.15, ink * 0.10, smoothstep(0.0, 0.45, skyUp));
        // what it holds: dark in the troughs, the colour coming through on a crest lit from behind
        float crest = clamp(w1.x / (0.20 * (0.55 + 0.75 * amp)) + rh * 3.0, 0.0, 1.2);
        vec3 deep = ink * (0.075 + 0.20 * level * crest + 0.26 * crest * crest);
        vec3 c = mix(deep, skyRefl, fres);

        // the moon's column: a tight highlight and a wide one, broken by every facet
        float sd = max(dot(refl, moon), 0.0);
        float gl = pow(sd, 420.0) * 2.4 + pow(sd, 42.0) * 0.20;
        c += hot * gl * (0.8 + 0.5 * chop);

        // foam: where the crest is steep and high, torn by noise. The ring leaves its own
        float stress = dot(grad, grad);
        // veins, never a patch: foam is a net of thin lines stretched by the wave that carries it
        float tear = vnoise(p * vec2(2.2, 4.6) + vec2(t * 0.35, -t * 0.2) + w1.yz * 2.0);
        float vein = 1.0 - abs(tear * 2.0 - 1.0);
        vein = pow(vein, 5.0) * (0.45 + 0.55 * vnoise(p * 13.0 - t * 0.5));
        float foam = smoothstep(0.84, 1.12, crest) * smoothstep(0.02, 0.15, stress + rh) * (0.25 + vein);
        foam += smoothstep(0.018, 0.09, rh) * vein * 1.6;
        foam *= exp(-Z * 0.045);
        c = mix(c, mix(ink, hot, 0.7) * (0.75 + 0.3 * level), clamp(foam, 0.0, 0.92));

        // the distance eats it, into the same haze the sky starts from
        col = mix(c, haze, smoothstep(14.0, 90.0, Z));
        a = 1.0;
    }

    a = clamp(a * dim, 0.0, 1.0);
    col = clamp(col * dim, 0.0, 1.6);
    fragColor = vec4(col * a, a) * qt_Opacity;   // premultiplied, Qt expects it
}
