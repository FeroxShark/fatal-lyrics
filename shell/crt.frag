#version 440
// fatal-lyrics — CRT mode.
//
// Takes the flat lyric layer rendered by Crt.qml and puts it inside a dying
// cathode ray tube: barrel glass, phosphor bloom, aperture grille, scanlines
// with a rolling bar, RGB misalignment, torn signal bands and static.
//
// Build:  qsb --glsl 100es,120,150 --hlsl 50 --msl 12 -o crt.frag.qsb crt.frag
// (there is a prebuilt crt.frag.qsb next to this file; rebuilding is only
// needed if you edit the shader)

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float t;          // seconds since the mode started
    float curvature;  // 0 = flat panel, 1 = fat 90s tube
    float scanline;   // depth of the horizontal comb
    float chroma;     // steady RGB misalignment
    float bloom;      // phosphor overdrive around bright text
    float noiseAmt;   // static
    float glitch;     // 0..1 burst: tearing, wave, extra chroma
    float roll;       // brightness bar rolling down the tube
    float alarm;      // 0..1 red critical wash
    float vignette;
    float pulse;      // 0..1 golpe de la canción: el tubo levanta con el ritmo
    float blink;      // 0..1 apagón corto, para los picos
    vec2 res;         // surface size in pixels
    vec3 tint;        // phosphor colour of this screen
};

layout(binding = 1) uniform sampler2D src;

float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    return fract(p * (p + p));
}

float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// glass: pushes the corners out like a real tube face
vec2 curve(vec2 uv) {
    uv = uv * 2.0 - 1.0;
    vec2 off = abs(uv.yx) / vec2(5.0, 3.6) * curvature;
    uv += uv * off * off;
    return uv * 0.5 + 0.5;
}

void main() {
    vec2 uv = curve(qt_TexCoord0);

    // signal interference: the picture breaks into horizontal bands that jump
    // sideways, and the whole raster snakes a little
    float bandH = 6.0 + 26.0 * hash11(floor(t * 3.0) + 11.0);
    float band = floor(uv.y * res.y / bandH);
    float pick = hash11(band * 1.7 + floor(t * 14.0) * 0.31);
    float shove = (hash11(band * 3.1 + floor(t * 14.0)) - 0.5);
    uv.x += shove * glitch * 0.09 * step(0.55, pick);
    uv.x += sin(uv.y * 34.0 + t * 5.0) * (0.0006 + glitch * 0.004);

    // out of tube: black bezel with a thin phosphor edge
    vec2 e = step(vec2(0.0), uv) * step(uv, vec2(1.0));
    float inside = e.x * e.y;
    if (inside < 0.5) {
        fragColor = vec4(0.0, 0.0, 0.0, qt_Opacity);
        return;
    }

    // RGB split: red drifts left, blue drifts right (worse while glitching)
    float ca = chroma * 0.0016 + glitch * 0.007;
    vec3 col;
    col.r = texture(src, uv + vec2(ca, 0.0)).r;
    col.g = texture(src, uv).g;
    col.b = texture(src, uv - vec2(ca, 0.0)).b;

    // Phosphor bleed. It has to work both ways round: bright letters on a dark
    // tube (the glyph spills light outwards) and a lit screen with dark letters
    // (the background eats into the glyph and a warm halo hugs its border, which
    // is what a real tube does and what the video looks like). A plain additive
    // glow only does the first: on a lit screen it just washes the picture out.
    if (bloom > 0.001) {
        vec3 glow = vec3(0.0);
        vec2 px = (2.6 / res) * (1.0 + glitch);
        glow += texture(src, uv + vec2( px.x,  0.0)).rgb;
        glow += texture(src, uv + vec2(-px.x,  0.0)).rgb;
        glow += texture(src, uv + vec2( 0.0,  px.y)).rgb;
        glow += texture(src, uv + vec2( 0.0, -px.y)).rgb;
        vec2 px2 = px * 2.7;
        glow += texture(src, uv + vec2( px2.x,  px2.y)).rgb;
        glow += texture(src, uv + vec2(-px2.x,  px2.y)).rgb;
        glow += texture(src, uv + vec2( px2.x, -px2.y)).rgb;
        glow += texture(src, uv + vec2(-px2.x, -px2.y)).rgb;
        glow *= 0.125;                     // media de las ocho muestras
        float lum = dot(col, vec3(0.3, 0.6, 0.1));
        float glum = dot(glow, vec3(0.3, 0.6, 0.1));
        float edge = abs(glum - lum);      // fuerte sólo cerca del borde del glifo
        // El sangrado va del lado CLARO. Si se reparte parejo, en una pantalla
        // prendida la luz se mete adentro de la letra oscura y se pierde el
        // contraste: el texto queda del color del fondo, apenas más apagado.
        float bright = step(glum, lum);
        col = mix(col, glow, 0.22 * bloom * bright);
        col += tint * edge * bloom * (0.22 + 0.85 * bright);
    }

    vec2 fc = uv * res;

    // scanlines: the comb crawls slowly so it never looks like a static texture
    float sl = 0.5 + 0.5 * cos(fc.y * 3.14159 + t * 1.6);
    col *= 1.0 - scanline * 0.55 * sl;

    // aperture grille: RGB triads, the reason CRT text never looks clean
    float tri = mod(fc.x, 3.0);
    vec3 mask = vec3(1.16, 0.86, 0.86);
    if (tri > 1.0 && tri <= 2.0) mask = vec3(0.86, 1.16, 0.86);
    else if (tri > 2.0) mask = vec3(0.86, 0.86, 1.16);
    col *= mix(vec3(1.0), mask, 0.55);

    // rolling bar: the classic bright band sliding down an out-of-sync tube
    float by = fract(t * 0.085);
    float d = abs(fract(uv.y - by + 0.5) - 0.5);
    col += tint * 0.05 * smoothstep(0.07, 0.0, d) * roll;

    // static, worse mid-glitch
    float n = hash21(fc + floor(t * 60.0));
    col += (n - 0.5) * (noiseAmt * 0.14 + glitch * 0.22);

    // block corruption during a burst
    if (glitch > 0.01) {
        vec2 bs = vec2(hash11(floor(t * 9.0)) * 60.0 + 20.0);
        vec2 cell = floor(fc / bs);
        float b = hash21(cell + floor(t * 9.0));
        if (b > 1.0 - 0.30 * glitch)
            col = mix(col, col.gbr * 1.4 + tint * 0.25, 0.6 * glitch);
    }

    // El titileo. La parte fija es el tubo (60 Hz y su inestabilidad), pero lo
    // que se ve es el otro: `pulse` llega con cada golpe de la canción, así que
    // la pantalla late CON la música en vez de parpadear por su cuenta.
    col *= 1.0 - 0.025 * sin(t * 377.0) - 0.02 * hash11(floor(t * 24.0));
    col *= 1.0 + pulse * (0.30 + 0.25 * hash11(floor(t * 11.0)));
    // y en los picos, el apagón corto de una tele a la que le falta corriente
    col *= 1.0 - blink * 0.82;

    // critical state: the whole tube washes red and pulses
    if (alarm > 0.001) {
        float pulse = 0.72 + 0.28 * sin(t * 16.0);
        vec3 hot = vec3(dot(col, vec3(0.35, 0.5, 0.15)));
        col = mix(col, hot * vec3(1.6, 0.16, 0.12) * pulse + col * 0.35, alarm);
    }

    // glass: vignette plus a faint sheen off the top-left of the tube face
    float v = pow(16.0 * uv.x * uv.y * (1.0 - uv.x) * (1.0 - uv.y), 0.22);
    col *= mix(1.0, v, vignette);
    col += vec3(0.012, 0.014, 0.02) * smoothstep(1.2, 0.0, uv.x + uv.y);

    fragColor = vec4(col, 1.0) * qt_Opacity;
}
