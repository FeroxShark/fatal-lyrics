#version 440
// fatal-lyrics — motivo `julia` (2026-10-22): el conjunto de Julia visto con las líneas de
// nivel del tiempo de escape, como el mapa de curvas de una isla que respira. Un número
// complejo `c` camina despacio por el borde de la cardioide de Mandelbrot (ahí el conjunto
// cambia de forma sin parar: dendritas, espirales, polvo) y la pantalla es lo que escapa
// de z² + c.
//   · el bombo (`pulse`, la envolvente del resorte de Thump.js) empuja `c` hacia afuera y
//     acerca la cámara: el conjunto se astilla un instante y vuelve con el mismo resorte
//   · el compás (`bn`, `since`): las líneas de nivel dan UN paso por tiempo hacia el
//     conjunto con el snap de Motion (OutExpo 320 ms) y se quedan quietas
//   · agudos (`fizz`): chispas sobre las líneas
//   · densidad (`dens`): más líneas de nivel y más brillo adentro del conjunto
//   · drop (`dropAmt`): se prende el relleno del conjunto
//
// Build:  /usr/lib/qt6/bin/qsb --glsl '100 es,120,150' -o julia.frag.qsb julia.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 ink;
    vec4 hot;
    vec4 bg;
    vec2 res;
    float drift;      // fase acumulada, nunca para
    float dens;       // 0..1
    float fizz;       // 0..1
    float pulse;      // 0..1: el golpe
    float bn;         // contador de tiempos
    float since;      // s desde el último tiempo
    float seed;
    float dropAmt;    // 0..1
    float quality;    // 0.5..1
};

float h11(float n) { return fract(sin(n * 12.9898 + 4.1414) * 43758.5453); }
float outExpo(float x) { return x >= 1.0 ? 1.0 : 1.0 - exp2(-10.0 * x); }

void main() {
    vec2 uv = (qt_TexCoord0 - 0.5) * res / min(res.x, res.y);
    // la cámara: gira despacio, respira, y el golpe la acerca
    float rot = drift * 0.035 + 0.6 * seed;
    float zoom = 1.55 - 0.10 * pulse + 0.06 * sin(drift * 0.21);
    vec2 z = vec2(uv.x * cos(rot) - uv.y * sin(rot), uv.x * sin(rot) + uv.y * cos(rot)) * zoom;

    // c: el borde de la cardioide, un poco más afuera; el golpe lo empuja
    float th = 1.1 + 0.9 * seed + drift * 0.11;
    vec2 e1 = vec2(cos(th), sin(th));
    vec2 e2 = vec2(cos(2.0 * th), sin(2.0 * th));
    vec2 c = (0.5 * e1 - 0.25 * e2) * (1.012 + 0.028 * pulse + 0.012 * sin(drift * 0.17));

    float maxIt = floor(30.0 + 26.0 * quality);
    float nu = 0.0;
    float trap = 1e3;
    bool inside = true;
    for (int i = 0; i < 56; i++) {
        if (float(i) >= maxIt) break;
        z = vec2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
        trap = min(trap, abs(length(z) - 0.42));
        float r2 = dot(z, z);
        if (r2 > 256.0) {
            // tiempo de escape suavizado
            nu = float(i) + 1.0 - log2(log2(r2) * 0.5);
            inside = false;
            break;
        }
    }

    float l;
    if (inside) {
        // adentro: las líneas del orbit-trap (una cruz que se pliega), que se prende con el drop
        float tr = exp(-trap * 9.0);
        l = 0.04 + 0.34 * tr * tr + (0.16 + 0.2 * dens) * dropAmt * (0.3 + tr);
    } else {
        // afuera: líneas de nivel; cada tiempo se corren un paso hacia el conjunto
        float freq = 0.34 + 0.10 * dens;
        float stepB = (mod(bn, 2.0) + outExpo(clamp(since / 0.32, 0.0, 1.0))) * 0.5;   // `bn` llega en miles
        float f = fract(nu * freq - stepB);
        float ridge = smoothstep(0.62, 0.92, 1.0 - abs(f - 0.5) * 2.0);
        float near = 0.16 + 0.84 * smoothstep(2.0, 13.0, nu);   // el halo: cerca del conjunto, más claro
        l = 0.04 + near * (0.12 + 0.88 * ridge);
        // agudos: chispas sobre las líneas
        float band = floor(nu * freq - stepB);
        float sp = step(0.82, h11(band * 3.1 + floor(drift * 3.0) + seed * 5.0)) * fizz;
        l += 0.45 * sp * ridge * near;
    }
    l *= 1.0 + 0.18 * pulse;

    vec3 col = mix(bg.rgb, ink.rgb, smoothstep(0.05, 0.62, l));
    col = mix(col, hot.rgb, smoothstep(0.70, 1.10, l));
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
