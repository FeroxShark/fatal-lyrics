#version 440
// fatal-lyrics — the sea.
//
// A field of individual points floating on water, seen from just above the
// surface. There is no mesh: every dot is its own particle, projected by hand
// with a perspective divide, and its height is solved analytically — travelling
// swell, fine chop, its own idle bob, and a damped ring that arrives late the
// further away it is. That last part is what makes it read as physics instead
// of a texture: a beat drops a stone in the water and the disturbance crosses
// the sea, each dot rising when the front reaches IT and ringing down at its
// own rate.
//
// Why a shader and not QML items: the wall is three screens, one of them at
// 200 Hz. A few hundred Rectangles with per-frame bindings is hundreds of
// thousands of JS evaluations a second. Here the whole sea is one draw call and
// the dots cost nothing to move.
//
// Build:  qsb --glsl 100es,120,150 --hlsl 50 --msl 12 -o ocean.frag.qsb ocean.frag

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
};

// --------------------------------------------------------------- the camera
// Eye one unit above the water, looking flat along it. A point at (X, height,
// Z) lands at screen y = HORIZON + (1 - height) / Z, x = X / Z. Everything
// below is that mapping and its inverse.
const float HORIZON = 0.34;
const float Z0 = 1.42;   // first row of dots that is still on screen
const float DZ = 0.14;   // row spacing, in world units
const float DX = 0.17;   // column spacing
const float DOTR = 0.021; // dot radius in world units
const float RIPV = 2.4;  // how fast a ring crosses the water

float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// A ring dropped at `c`: the dot only moves once the front gets there, then it
// rings down. Delay by distance is the whole trick — without it every dot in
// the sea jumps on the same beat and the wall pulses like a lamp.
float ripple(vec2 p, vec4 r) {
    float age = t - r.z;
    if (r.w < 0.001 || age < 0.0 || age > 6.0)
        return 0.0;
    float dist = distance(p, r.xy);
    float front = age * RIPV;
    float d = dist - front;
    float env = exp(-d * d * 1.6)        // the packet, tight around the front
              * exp(-age * 0.85)         // the water settling
              * exp(-dist * 0.10);       // and it loses strength as it spreads
    return sin(d * 4.2) * env * r.w;
}

// Height of ONE dot. `lat` is its lattice index, which is what gives each point
// a phase and a bob rate of its own instead of the whole sheet moving as one.
float waterAt(vec2 lat, vec2 p) {
    float tt = t * speed;
    float h = sin(p.x * 1.35 + tt * 0.95) * 0.55
            + sin(p.y * 0.95 - tt * 0.75) * 0.45 * (0.55 + 0.9 * swell);
    h += sin((p.x * 0.8 + p.y * 1.25) + tt * 1.55) * 0.26;
    h += sin((p.x * 3.4 - p.y * 2.6) - tt * 2.7) * 0.14 * (0.25 + chop);

    float own = hash21(lat);
    h += sin(tt * (1.5 + 1.3 * own) + own * 6.283) * 0.20 * (0.35 + 0.8 * level);

    h *= 0.052 * (0.55 + 0.75 * amp);
    h += (ripple(p, rip1) + ripple(p, rip2)) * 0.020 * amp;
    return h;
}

void main() {
    vec2 uv = qt_TexCoord0;
    float aspect = res.x / max(res.y, 1.0);
    float sx = (uv.x - 0.5) * aspect;      // screen x in units of screen HEIGHT
    float dy = uv.y - HORIZON;

    vec3 col = vec3(0.0);
    float a = 0.0;

    // the far edge: where the dots run out of resolution they melt into a band.
    // Kept faint on purpose — a hard line reads as a drawn horizon, and what
    // sells the distance is the dots getting smaller, not a stripe.
    float glow = exp(-abs(dy) * 60.0) * 0.26 + exp(-abs(dy) * 11.0) * 0.09;
    col += mix(ink, hot, 0.35) * glow * (0.5 + 0.5 * level);
    a = max(a, glow * 0.7);

    if (dy > 0.0008) {
        // the whole field creeps towards the eye; rows slide in from the far
        // side instead of popping, because the lattice itself is offset
        float drift = fract(t * speed * 0.055) * DZ;
        float z = 1.0 / dy;                       // depth of flat water here
        float jf = (z - Z0 + drift) / DZ;
        float worldX = sx * z;
        int j0 = int(floor(jf));

        for (int dj = -2; dj <= 2; dj++) {
            int j = j0 + dj;
            if (j < 0)
                continue;
            float Z = Z0 + float(j) * DZ - drift;
            if (Z < 0.6)
                continue;

            // odd rows sit half a step across, so the field reads as water and
            // not as graph paper
            float stagger = mod(float(j), 2.0) * 0.5;
            float ifl = worldX / DX - stagger;
            int i0 = int(floor(ifl));

            // techo al radio: sin él, la fila más cercana son manchones de
            // 20 px y deja de leerse como puntos sueltos
            float rad = clamp(DOTR / Z * res.y, 0.85, res.y * 0.011);

            for (int di = -1; di <= 1; di++) {
                int i = i0 + di;
                float X = (float(i) + stagger) * DX;
                float px = X / Z;

                // La altura mueve al punto en VERTICAL y nada más: su x en
                // pantalla ya se sabe. Descartar por x acá ahorra la ola entera
                // (y sus dos ondas) en la mayoría de los candidatos.
                float dx = (sx - px) * res.y;
                if (abs(dx) > rad + 1.0)
                    continue;

                vec2 lat = vec2(float(i), float(j));
                float h = waterAt(lat, vec2(X, Z));
                float py = HORIZON + (1.0 - h) / Z;

                // distancia en píxeles, así el punto es redondo en cualquier
                // relación de aspecto
                vec2 d = vec2(dx, (uv.y - py) * res.y);
                float dotv = smoothstep(rad, rad * 0.28, length(d));
                if (dotv <= 0.001)
                    continue;

                float fade = exp(-(Z - Z0) * haze * 0.10);
                // Crests catch the light and troughs FADE OUT — they are not
                // painted darker. A dot darker than the water reads as a hole
                // punched in the picture, and it breaks on a lit palette too,
                // where the background is the bright thing.
                float crest = clamp(h * 22.0 + 0.5, 0.0, 1.0);
                vec3 c = mix(ink, hot, crest * crest);
                // el piso no es cero: con el pozo apagado del todo, media
                // pantalla se quedaba vacía cada vez que pasaba una ola larga y
                // el mar parecía existir sólo en una franja
                float bright = (0.45 + 0.75 * crest) * fade;

                col += c * dotv * bright;
                a = max(a, dotv * bright * 0.92);
            }
        }
    }

    a = clamp(a * dim, 0.0, 1.0);
    col = clamp(col * dim, 0.0, 1.6);
    fragColor = vec4(col * a, a) * qt_Opacity;   // premultiplied, Qt expects it
}
