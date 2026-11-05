#version 440
// fatal-lyrics — el ojo (`Eye.qml`). Una almendra de alambre con un iris CIRCULAR que el párpado tapa:
// el párpado no achata el iris, le corta una tajada. Es la forma del ojo del videoclip (radios en
// la esclera, anillos en el iris), con lo que le faltaba para que se lea como un ojo: fibras en el
// iris, el borde oscuro del limbo, el brillo húmedo, la sombra del párpado de arriba y el pliegue.
//
// Build:  /usr/lib/qt6/bin/qsb --glsl '100 es,120,150' -o eye.frag.qsb eye.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 ink;
    vec4 hot;
    vec2 res;
    float aperture;   // 0..1 cuánto deja ver el párpado
    float dx;         // px: hacia dónde mira
    float pupil;      // radio de la pupila, en px
    float pulse;      // 0..1 el golpe
    float seed;
};

const float TAU = 6.2831853;
float h11(float n) { return fract(sin(n * 12.9898 + 4.1414) * 43758.5453); }
float angNoise(float a, float k) {
    float x = a / TAU * k;
    float i = floor(x), f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(h11(mod(i, k) + seed * 91.0), h11(mod(i + 1.0, k) + seed * 91.0), f);
}

void main() {
    vec2 p = qt_TexCoord0 * res - 0.5 * res;
    float W = res.x, H = res.y;
    float lw = max(1.5, H * 0.012);
    float halfW = W * 0.5 - lw;
    float u = clamp(p.x / halfW, -1.0, 1.0);

    // el arco: lo que era la cuadrática del Canvas, que llega a la mitad de su punto de control
    float arch = 0.47 * H * aperture;
    float top = arch * (1.0 - u * u);
    float slope = 2.0 * arch * u / halfW;
    float sd = (abs(p.y) - top) / sqrt(1.0 + slope * slope);
    if (abs(p.x) > halfW) sd = max(sd, length(vec2(abs(p.x) - halfW, p.y)));
    float inside = smoothstep(0.7, -0.7, sd);

    vec3 c = vec3(0.0);
    float alpha = 0.0;

    if (inside > 0.0) {
        vec2 q = p - vec2(dx, 0.0);
        float r = length(q);
        float R = H * 0.30;
        float a = atan(q.y, q.x);
        if (a < 0.0) a += TAU;
        float pxA = 44.0 / TAU;

        // la esclera: apenas llena, y los radios que se abren hasta la punta, achatados con el párpado
        vec2 qs = vec2(p.x - dx * (1.0 - abs(u)), p.y / max(aperture, 0.12));
        float as = atan(qs.y, qs.x);
        float rs = length(qs);
        float ds = abs(fract(as * pxA + 0.5) - 0.5) / pxA * rs;
        float spoke = smoothstep(lw * 0.65, lw * 0.15, ds) * step(R, r);
        float sc = 0.05 + 0.42 * spoke * (1.0 - 0.5 * smoothstep(0.5, 1.0, abs(u)));

        // el iris
        float irisA = 0.0;
        vec3 irisC = vec3(0.0);
        if (r < R + 2.0) {
            float n = angNoise(a, 90.0) * 0.6 + angNoise(a, 233.0) * 0.4;
            float rr = r / R;
            // fibras: radios finos que salen de la pupila, y se cortan en el collar
            float dsp = abs(fract(a * pxA + 0.5) - 0.5) / pxA * r;
            float fib = smoothstep(lw * 0.55, lw * 0.12, dsp) * 0.48;
            float ringK = fract(rr * 6.0 + 0.5);
            float ring = smoothstep(lw * 0.75, lw * 0.2, abs(ringK - 0.5) / 6.0 * R) * 0.62;
            float collar = exp(-pow((rr - 0.46) / 0.08, 2.0)) * 0.55 * (0.5 + n);
            float fill = (0.10 + 0.34 * n * smoothstep(0.2, 0.9, rr)) * (1.0 + 0.8 * pulse);
            float limbus = smoothstep(0.82, 1.0, rr);
            float v = max(max(fib, ring), fill + collar);
            v *= 1.0 - 0.45 * limbus;
            v += 0.85 * smoothstep(lw * 1.3, lw * 0.3, abs(r - R));   // el borde del iris
            irisC = mix(ink.rgb, hot.rgb, 0.10 + 0.5 * collar + 0.4 * pulse * smoothstep(0.7, 0.3, rr));
            irisA = v;
        }
        float inIris = smoothstep(R + 1.0, R - 1.0, r);

        // la sombra del párpado de arriba cae sobre lo que hay debajo
        float shadeTop = smoothstep(0.0, top * 0.55 + 1.0, p.y + top);
        float shade = mix(0.42, 1.0, shadeTop);

        c = (ink.rgb * sc * (1.0 - inIris) + irisC * irisA * inIris) * shade;
        alpha = max(sc * (1.0 - inIris), min(irisA, 1.0) * inIris) * shade;

        // la pupila: un pozo oscuro con su aro caliente; adentro, nada
        float pu = smoothstep(pupil + 1.0, pupil - 1.0, r);
        float puRing = smoothstep(lw * 1.0, lw * 0.25, abs(r - pupil));
        c = mix(c, vec3(0.0), pu);
        alpha = mix(alpha, 0.92, pu);
        c += hot.rgb * puRing * 0.95;
        alpha = max(alpha, puRing * 0.95);

        // el brillo húmedo: uno grande arriba a la izquierda, uno chico abajo
        vec2 g1 = (q - vec2(-0.34, -0.36) * R) / (R * vec2(0.20, 0.15));
        vec2 g2 = (q - vec2(0.30, 0.38) * R) / (R * 0.07);
        float gl = smoothstep(1.0, 0.72, length(g1)) + 0.65 * smoothstep(1.0, 0.6, length(g2));
        c += hot.rgb * gl * shadeTop;
        alpha = max(alpha, min(gl, 1.0) * shadeTop);

        c *= inside;
        alpha *= inside;
    }

    // el párpado: la línea, más gruesa arriba
    float w = p.y < 0.0 ? lw * 1.15 : lw * 0.7;
    float rim = smoothstep(w + 0.7, w - 0.3, abs(sd));
    // el pliegue, por encima del párpado, y las pestañas de arriba
    float foldTop = (arch + H * 0.055) * (1.0 - u * u);
    float fold = p.y < 0.0
        ? smoothstep(lw * 0.8, lw * 0.2, abs(-p.y - foldTop)) * 0.40 * smoothstep(0.98, 0.72, abs(u)) : 0.0;
    float lashN = 58.0;
    float lu = fract((u + 1.0) * 0.5 * lashN);
    float lash = 0.0;
    if (p.y < 0.0 && sd > 0.0) {
        float len = H * 0.032 * (0.45 + 0.55 * h11(floor((u + 1.0) * 0.5 * lashN) + seed * 7.0)) * smoothstep(1.0, 0.75, abs(u));
        lash = smoothstep(0.16, 0.05, abs(lu - 0.5 - sd / (H * 0.06) * u * 0.8)) * step(sd, len) * 0.75;
    }
    float line = max(rim, max(fold * (1.0 - inside), lash));
    c += mix(ink.rgb, hot.rgb, 0.22 * pulse) * line * (1.0 - alpha);
    alpha = max(alpha, line);

    alpha = clamp(alpha, 0.0, 1.0);
    fragColor = vec4(min(c, vec3(1.0)), alpha) * qt_Opacity;
}
