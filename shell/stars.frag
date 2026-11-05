#version 440
// fatal-lyrics — the jump to hyperspace (motif `stars`).
//
// A real sky you fly through: a dust of fixed far stars and a faint nebula that do not move, and in
// front of them layers of near stars that come out of the vanishing point. In the calm they barely
// crawl; on a kick the streaks pull longer; in the drop they become lines and turn hot.
//
// It used to be up to 900 rectangles per screen, each one with its own bindings (Ferox 2026-11-05: it
// read as a few dots and cost more than a shader). Here nothing is iterated: the grid lives in
// LOG-POLAR space (angle, log r). A star flying towards the camera at constant speed moves along a
// straight line at constant speed there, and grows with r on its own, which is why the perspective
// comes out right with no 3D at all. Each pixel looks at one cell per layer.
//
// And somewhere to go: every so often a planet comes out of the vanishing point and goes past, and a
// ship seen from behind flies through all of it, leaning into its turns, its engines flaring on the
// kick (Gonza's idea, Ferox 2026-11-05).
//
// WALL: it works in canvas pixels relative to the focus, so the field is one across every screen.
//
// Build:  qsb --glsl "100 es,120,150" -o stars.frag.qsb stars.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float travel;   // accumulated distance flown: never a clock times a speed, see Stars.qml
    float warp;     // 0 cruising .. 1 in the jump
    float level;    // volume
    float kick;     // low band: the streaks pull on the kick
    float spanPx;   // px per unit (the short side of a screen)
    vec4 view;      // this screen's window on the canvas: x, y, w, h in px
    vec2 fo;        // where the stars come from, canvas px
    vec3 ink;
    vec3 hot;
};

const float TAU = 6.2831853;
const float LOG_PER_TRAVEL = 1.6;  // log-radius units per unit of `travel`
const float ASPECT = 6.0;          // cells are this many times longer than wide, so a streak fits inside

float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x),
               mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * vnoise(p);
        p = p * 2.03 + vec2(17.0, 9.0);
        a *= 0.5;
    }
    return v;
}

// One layer of flying stars. Returns (brightness, how hot).
vec2 layer(float ang, float lr, float r, float n, float parallax, float seed, float streak) {
    float cw = TAU / n;              // cell width in log-polar units: conformal, so also px / r
    float ch = cw * ASPECT;
    float cx = ang / cw;
    float col = floor(cx);
    col = mod(col, n);               // closes the seam at ±π
    // each column slides by its own amount, so the heads never line up in rings
    float cy = (lr - travel * LOG_PER_TRAVEL * parallax) / ch + hash21(vec2(col, seed)) * 13.0;
    float row = floor(cy);
    vec2 id = vec2(col, mod(row, 4096.0));
    float h = hash21(id + seed * 7.3);
    if (h < 0.38)
        return vec2(0.0);
    vec2 f = vec2(fract(cx) - 0.5, fract(cy));
    float h2 = hash21(id.yx + seed * 3.1);
    f.x -= (h2 - 0.5) * 0.6;

    // the head goes on the outer end of the cell and the tail reaches back towards the focus
    float head = 0.97;
    float tail = head - clamp(streak * (0.6 + 0.8 * h2), 0.012, 0.94);
    float dy = (f.y - clamp(f.y, tail, head)) * ch * r;
    float dx = f.x * cw * r;
    float size = clamp((0.05 + 0.10 * h) * cw * r, 1.25 / spanPx, 0.0052);
    float d2 = (dx * dx + dy * dy) / (size * size);
    float body = exp(-d2);
    float halo = 0.22 / (1.0 + d2 * 0.35);

    float along = clamp((f.y - tail) / max(head - tail, 0.001), 0.0, 1.0);
    float b = (body + halo) * mix(0.18, 1.0, along * along) * (0.45 + 0.55 * h);
    // born out of nothing near the vanishing point, where the cells are thinner than a pixel
    b *= smoothstep(0.035, 0.24, r);
    return vec2(b, step(0.86, h2));
}

// A planet grows out of the vanishing point: same log-polar idea with a few big cells. Returns the
// colour and the coverage.
vec4 planet(vec2 p, float ang, float lr) {
    const float N = 5.0;
    const float CH = 2.3;
    float cw = TAU / N;
    float col = mod(floor(ang / cw), N);
    float off = travel * LOG_PER_TRAVEL * 0.33;
    float cy = (lr - off) / CH + hash21(vec2(col, 41.0)) * 5.0;
    float row = floor(cy);
    vec2 id = vec2(col, mod(row, 512.0));
    float h = hash21(id + 11.0);
    if (h < 0.70)
        return vec4(0.0);
    float h2 = hash21(id + 23.0), h3 = hash21(id + 37.0), h4 = hash21(id + 53.0);
    float angC = (col + 0.5 + (h2 - 0.5) * 0.3) * cw - 3.14159265;
    float lrC = (row + 0.5 - hash21(vec2(col, 41.0)) * 5.0) * CH + off;
    float rC = exp(lrC);
    vec2 C = rC * vec2(cos(angC), sin(angC));
    float R = min(rC * (0.13 + 0.09 * h3), 0.6);
    vec2 d = (p - C) / R;
    float l2 = dot(d, d);
    float born = smoothstep(0.10, 0.34, rC);
    if (born <= 0.0 || l2 > 7.0)
        return vec4(0.0);

    float px = 1.0 / (spanPx * R);
    vec3 base = mix(ink, hot, 0.15 + 0.45 * h4) * vec3(1.0 + (h3 - 0.5) * 0.8, 1.0, 1.0 - (h3 - 0.5) * 0.8);
    vec3 c = vec3(0.0);
    float a = 0.0;

    // the rings go behind and in front, tilted; only some planets have them
    bool ringed = h3 > 0.55;
    float tilt = (h2 - 0.5) * 1.4;
    vec2 rq = vec2(d.x * cos(tilt) + d.y * sin(tilt), (-d.x * sin(tilt) + d.y * cos(tilt)) * 3.4);
    float rr = length(rq);
    float ring = ringed ? smoothstep(1.32, 1.36, rr) * smoothstep(2.25, 2.15, rr)
                        * (0.45 + 0.4 * sin(rr * 34.0 + h * 9.0) * sin(rr * 11.0)) : 0.0;
    if (ring > 0.0 && rq.y < 0.0) {
        c = base * 0.75 * ring;
        a = ring;
    }

    if (l2 < 1.0 + 2.0 * px) {
        float z = sqrt(max(1.0 - l2, 0.0));
        vec3 n = vec3(d, z);
        // bands for a gas giant, blotches for a rock
        vec2 uv = vec2(atan(d.x, z) * (1.0 + h4), d.y / (0.55 + 0.45 * z));
        float surf = h4 > 0.5
            ? fbm(vec2(uv.x * 1.1 + h * 40.0, uv.y * 7.0 + h2 * 20.0))
            : fbm(uv * 3.4 + h * 40.0);
        float lamb = dot(n, normalize(vec3(-0.78, -0.50, 0.36)));
        float lit = smoothstep(0.0, 0.62, lamb);
        vec3 body = base * (0.30 + 1.05 * surf) * (0.035 + 0.965 * lit);
        // thin air on the lit limb
        body += mix(base, hot, 0.5) * pow(1.0 - z, 4.0) * lit * 0.8;
        float m = smoothstep(1.0 + px, 1.0 - px, sqrt(l2));
        c = mix(c, body, m);
        a = mix(a, 1.0, m);
    }
    if (ring > 0.0 && rq.y >= 0.0) {
        c = mix(c, base * 0.85, ring);
        a = max(a, ring);
    }
    return vec4(c * born, a * born);
}

float sdTri(vec2 p, vec2 a, vec2 b, vec2 c) {
    vec2 e0 = b - a, e1 = c - b, e2 = a - c;
    vec2 v0 = p - a, v1 = p - b, v2 = p - c;
    vec2 q0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    vec2 q1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    vec2 q2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    vec2 d = min(min(vec2(dot(q0, q0), s * (v0.x * e0.y - v0.y * e0.x)),
                     vec2(dot(q1, q1), s * (v1.x * e1.y - v1.y * e1.x))),
                 vec2(dot(q2, q2), s * (v2.x * e2.y - v2.y * e2.x)));
    return -sqrt(d.x) * sign(d.y);
}

// The ship, from behind: a body, two swept wings with their tip pods, a fin and three engines. Dark
// and opaque, so it reads as a silhouette against any face. `p` from the focus, in units of span.
vec4 ship(vec2 p) {
    float sway = sin(travel * 0.55);
    float size = 0.17 * (1.0 - 0.14 * warp);
    vec2 pos = vec2(sway * 0.075, 0.395 - 0.03 * warp + 0.01 * sin(travel * 1.3));
    float bank = cos(travel * 0.55) * 0.24;
    vec2 q = (p - pos) / size;
    q = vec2(q.x * cos(bank) + q.y * sin(bank), -q.x * sin(bank) + q.y * cos(bank));
    float flare = 1.0 + 1.6 * kick + 1.4 * warp;
    if (dot(q, q) > 5.0 + 6.0 * flare)
        return vec4(0.0);

    float px = 1.0 / (spanPx * size);
    vec2 m = vec2(abs(q.x), q.y);
    float hull = (length(q / vec2(0.30, 0.19)) - 1.0) * 0.19;
    float wing = sdTri(m, vec2(0.18, -0.09), vec2(1.02, 0.17), vec2(0.18, 0.16));
    float pod = length(max(abs(m - vec2(0.97, 0.10)) - vec2(0.012, 0.075), 0.0)) - 0.02;
    float fin = sdTri(q, vec2(-0.07, -0.13), vec2(0.07, -0.13), vec2(0.0, -0.50));
    float d = min(min(hull, wing), min(pod, fin));

    float body = smoothstep(px, -px, d);
    vec3 c = vec3(0.0);
    float a = 0.0;
    if (body > 0.0) {
        // lit from above, with a bright edge so it never melts into a dark sky
        float top = clamp(0.5 - q.y * 1.2, 0.0, 1.0);
        vec3 metal = mix(ink * 0.05, mix(ink, hot, 0.3) * 0.36, top * top);
        metal += mix(ink, hot, 0.5) * smoothstep(-0.02, -0.002, d) * 0.55;
        metal *= 1.0 - 0.45 * smoothstep(0.012, 0.0, abs(wing + 0.05));
        c = metal * body;
        a = body;
    }
    // the engines: hot core, soft halo that grows on the kick and in the jump
    vec2 e1 = vec2(m.x - 0.15, m.y - 0.045);
    vec2 e2 = vec2(q.x, q.y + 0.045);
    float l = min(dot(e1, e1), dot(e2, e2) * 1.5);
    float core = smoothstep(0.0072, 0.0035, l);
    float halo = 0.012 * flare / (l + 0.012 * flare) * 0.75;
    vec3 fire = mix(mix(ink, hot, 0.55), hot, core);
    c += fire * (core + halo);
    a = clamp(a + core + halo, 0.0, 1.0);
    return vec4(c, a);
}

void main() {
    vec2 px = view.xy + qt_TexCoord0 * view.zw;
    vec2 p = (px - fo) / spanPx;     // from the focus
    vec2 w = px / spanPx;            // fixed on the canvas: the far sky does not follow the focus
    float r = max(length(p), 0.0008);
    float ang = atan(p.y, p.x) + 3.14159265;
    float lr = log(r);

    // ---- what does not move: the nebula and the dust ----
    float n1 = fbm(w * 1.3 + vec2(3.1, 7.7));
    float n2 = fbm(w * 2.6 - n1 * 1.4 + vec2(11.0, 2.0));
    float cloud = smoothstep(0.42, 0.86, n1) * (0.35 + 0.65 * n2);
    vec3 col = mix(ink, hot, 0.15) * cloud * 0.16;
    float alpha = cloud * 0.16;

    vec2 g = w * 95.0;
    vec2 gi = floor(g);
    float gh = hash21(gi);
    if (gh > 0.93) {
        vec2 gf = fract(g) - 0.25 - 0.5 * vec2(hash21(gi + 3.7), hash21(gi + 9.1));
        float tw = 0.65 + 0.35 * sin(travel * 9.0 + gh * 300.0);
        float dust = exp(-dot(gf, gf) * 130.0) * tw * (0.25 + 8.0 * (gh - 0.93));
        col += mix(ink, hot, 0.55) * dust * 0.8;
        alpha += dust * 0.8;
    }

    // ---- what flies past ----
    float streak = 0.015 + 0.04 * level + 0.13 * kick * kick + 0.80 * warp;
    float bright = 0.75 + 0.45 * level + 0.5 * warp;
    vec2 a = layer(ang, lr, r, 170.0, 0.46, 1.0, streak * 0.8);
    vec2 b = layer(ang + 1.3, lr, r, 110.0, 0.62, 2.0, streak);
    vec2 c = layer(ang + 2.9, lr, r, 70.0, 0.80, 3.0, streak);
    vec2 d = layer(ang + 4.1, lr, r, 42.0, 1.00, 4.0, streak * 1.1);
    float s = (a.x * 0.55 + b.x * 0.75 + c.x * 0.95 + d.x * 1.1) * bright;
    float heat = clamp(max(max(a.y * a.x, b.y * b.x), max(c.y * c.x, d.y * d.x)) + 0.75 * warp, 0.0, 1.0);
    col += mix(mix(ink, hot, 0.35), hot, heat) * s;
    alpha += s;

    // the place you are flying to: only a glow, and it opens up in the jump
    float core = exp(-r * r * mix(95.0, 22.0, warp)) * (0.10 + 0.45 * warp);
    col += mix(ink, hot, 0.5) * core;
    alpha += core;

    vec4 pl = planet(p, ang, lr);
    col = col * (1.0 - pl.a) + pl.rgb;
    alpha = alpha * (1.0 - pl.a) + pl.a;

    vec4 sh = ship(p);
    col = col * (1.0 - sh.a) + sh.rgb;
    alpha = alpha * (1.0 - sh.a) + sh.a;

    // premultiplied, and not a colour above the alpha: on a light face the same thing stays legible
    alpha = clamp(alpha, 0.0, 1.0);
    col = min(col, vec3(alpha));
    fragColor = vec4(col, alpha) * qt_Opacity;
}
