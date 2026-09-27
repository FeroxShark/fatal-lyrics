#version 440
// fatal-lyrics showreel — el vidrio que va encima de TODO el reel.
//
// Una pasada: curvatura, prendido/apagado del tubo (punto → raya → imagen y
// al revés), glitch de franjas y bloques (el PUENTE entre escenas, nunca un
// efecto que dura), RGB split, inversión y destello de los golpes, scanlines,
// grano y viñeta. El reel no sabe nada de esto: le pasa números por uniform.
//
// Build:  qsb --glsl "100 es,120,150" -o post.frag.qsb post.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float seed;       // cambia por cuadro durante el glitch
    float glitch;     // 0..1 franjas + bloques
    float chroma;     // px de separación RGB
    float flash;      // 0..1 a blanco
    float invert;     // 0..1 negativo
    float curve;      // curvatura del vidrio
    float scan;       // fuerza de scanlines
    float grain;      // grano
    float tubeX;      // 1 = ancho completo, ~0 = punto
    float tubeY;      // 1 = alto completo, ~0 = raya
    float glow;       // brillo de la raya/punto del tubo
    vec2 res;
};

layout(binding = 1) uniform sampler2D source;

float hash1(float n) { return fract(sin(n * 127.1 + 311.7) * 43758.5453); }
float hash2(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 cc = uv - 0.5;

    // vidrio curvo
    float r2 = dot(cc, cc);
    vec2 cuv = 0.5 + cc * (1.0 + curve * r2);

    // el tubo: la imagen se aplasta hacia la raya/el punto del centro
    vec2 sq = vec2(max(tubeX, 0.0005), max(tubeY, 0.0005));
    vec2 q = (cuv - 0.5) / sq + 0.5;
    bool inside = q.x >= 0.0 && q.x <= 1.0 && q.y >= 0.0 && q.y <= 1.0
               && cuv.x >= 0.0 && cuv.x <= 1.0 && cuv.y >= 0.0 && cuv.y <= 1.0;

    // glitch: franjas horizontales corridas + bloques desplazados
    float g = glitch;
    if (g > 0.001) {
        float band = floor(q.y * 42.0 + seed * 7.0);
        if (hash1(band + seed * 13.0) < g * 0.55)
            q.x += (hash1(band * 1.7 + seed) - 0.5) * 0.22 * g;
        vec2 blk = floor(q * vec2(24.0, 14.0));
        if (hash2(blk + seed * 3.3) < g * 0.22)
            q += (vec2(hash2(blk + 3.1 + seed), hash2(blk + 7.7 + seed)) - 0.5) * 0.14 * g;
    }

    float ch = (chroma + g * 18.0) / res.x;
    vec3 col;
    col.r = texture(source, q + vec2(ch, 0.0)).r;
    col.g = texture(source, q).g;
    col.b = texture(source, q - vec2(ch, 0.0)).b;
    if (!inside) col = vec3(0.0);

    // una franja de cada tanto se "quema" (línea de datos rota)
    if (g > 0.001) {
        float row = floor(q.y * res.y / 3.0);
        if (hash1(row + seed * 5.0) < g * 0.04) col = vec3(hash1(row), 0.9, 1.0) * 0.9;
    }

    col = mix(col, 1.0 - col, invert);
    col = mix(col, vec3(1.0), flash);

    // aplastado, el mismo haz concentra la luz
    float squeeze = 1.0 / (sq.x * sq.y);
    col *= mix(1.0, 1.6, clamp((squeeze - 1.0) * 0.1, 0.0, 1.0));

    // scanlines + grano + viñeta
    float sl = 0.5 + 0.5 * sin(cuv.y * res.y * 3.14159265);
    col *= 1.0 - scan * (1.0 - sl);
    col += (hash2(uv * res + fract(time * 61.0) * 100.0) - 0.5) * grain;
    float vig = smoothstep(0.95, 0.35, length(cc * vec2(1.0, 0.8)));
    col *= mix(0.72, 1.0, vig);

    // la raya / el punto del tubo, brillando por encima de todo
    if (glow > 0.001) {
        vec2 d = (cuv - 0.5) * res;
        float wx = max(sq.x * res.x * 0.5, 2.0);
        float wy = max(sq.y * res.y * 0.5, 1.5);
        float lx = max(abs(d.x) - wx, 0.0);
        float ly = max(abs(d.y) - wy, 0.0);
        float dist = length(vec2(lx, ly));
        col += vec3(0.85, 0.95, 1.0) * glow * (exp(-dist / 3.0) + 0.35 * exp(-dist / 28.0));
    }

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0) * qt_Opacity;
}
