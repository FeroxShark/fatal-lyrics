#version 440
// fatal-lyrics — CRT mode.
//
// Second pass of the tube: takes the picture that signal.frag left (the flat
// lyric layer after its trip down the cable) and puts it inside a dying
// cathode ray tube: barrel glass, phosphor bloom, aperture grille, scanlines
// with a rolling bar, RGB misalignment, torn signal bands and static.
//
// Build:  /usr/lib/qt6/bin/qsb --glsl '100 es,120,150' -o crt.frag.qsb crt.frag
// qsb is not on PATH; those are the three targets the committed crt.frag.qsb
// carries, next to the SPIR-V qsb always emits. Rebuilding is only needed if
// you edit this file — and it IS needed: a uniform that is not in the .qsb
// leaves the ShaderEffect property bound to nothing, without a warning.

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
    float rollPhase;  // 0..1: where the bar is (a lap every 4 beats when the tempo is known)
    float alarm;      // 0..1 red critical wash
    float vignette;
    float pulse;      // 0..1 golpe de la canción: el tubo levanta con el ritmo
    float blink;      // 0..1 apagón corto, para los picos
    // the interlaced entrance: the line shows up on half the scanlines first
    float interlacePhase;  // 0 = off, 1 = even rows only, 2 = odd rows only
    // el tubo apagado (tanda 6, corrida 0): 1 = prendido, 0 = apagado. Va
    // ANTES del ruido estático: el resto de fósforo (`noiseAmt` al 3 %) tiene
    // que quedar visible aunque esto llegue a 0, o se lee "desenchufado".
    float tubeLevel;
    // el tubo elegido (tanda 7, corrida 2): qué máscara lleva el vidrio y si la
    // señal se vuelve fósforo de un solo color. Con tube=custom valen 0 / 3 / 0 y
    // esto da EXACTAMENTE lo de antes.
    float maskType;   // 0 = rejilla de apertura, 1 = slot mask, 2 = puntos (shadow mask)
    float maskPitch;  // píxeles por tríada RGB (3 = la de siempre)
    float mono;       // 0..1: luminancia x monoTint (P1 verde, P3 ámbar)
    // el degauss (tanda 7, corrida 6): 1 = recién arranca, 0 = terminó. Sólo lo mueve el intro de
    // tema; en 0 el shader da EXACTAMENTE lo de antes.
    float degauss;
    vec2 res;         // surface size in pixels
    vec3 tint;        // phosphor colour of this screen
    vec3 monoTint;    // color del fósforo del tubo monocromo
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

// gira el color alrededor del eje gris (los anillos de pureza del degauss)
vec3 hueTurn(vec3 c, float a) {
    const vec3 k = vec3(0.57735);
    float ca = cos(a);
    return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

// How much of a pattern survives on screen (tanda 8). `f` is its frequency in
// cycles per SCREEN pixel. Up to ~0.36 it is drawn whole; from there to 0.48 it
// fades to nothing, because a comb that close to Nyquist does not draw itself:
// it beats against the pixel grid, and through the curvature (which stretches
// the frequency a little more towards every corner) the beat draws circles in
// the corners and a star in the middle.
float keepAt(float f) {
    return 1.0 - smoothstep(0.36, 0.48, f);
}

void main() {
    vec2 uv = curve(qt_TexCoord0);
    // The footprint of one screen pixel in tube pixels, taken HERE: after the
    // glass and before the glitch shoves bands sideways (a derivative across a
    // band boundary spikes and would carve lines of faded mask along the band
    // edges), and before the early return, where the derivatives are still
    // defined for the whole quad. Each row is the gradient of one tube axis.
    vec2 tp = uv * res;
    vec2 gx = vec2(dFdx(tp.x), dFdy(tp.x));
    vec2 gy = vec2(dFdx(tp.y), dFdy(tp.y));
    float kx = length(gx);   // tube px per screen px, across
    float ky = length(gy);   // and down

    // degauss: la bobina desmagnetiza el vidrio y la imagen ondula desde el centro hacia
    // afuera, cada vez menos. Se aplica sobre la geometría (después de la curvatura), así
    // la onda sigue la cara del tubo y no un rectángulo.
    vec2 dgc = uv - 0.5;
    float dgd = length(dgc * vec2(res.x / res.y, 1.0));
    if (degauss > 0.001) {
        float dgw = sin(dgd * 26.0 - t * 20.0);
        uv += normalize(dgc + 1e-5) * dgw * degauss * degauss * 0.028;
    }

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

    // degauss: los anillos de pureza (el tinte rota según la distancia al centro, como el
    // arcoíris de una bobina que todavía no se calmó) y un destello chico al arrancar
    if (degauss > 0.001) {
        col = hueTurn(col, degauss * 2.4 * sin(dgd * 15.0 - t * 9.0));
        col += tint * pow(degauss, 6.0) * 0.55 * smoothstep(1.1, 0.0, dgd);
    }

    // fósforo de un solo color (tanda 7, corrida 2): P1 verde, P3 ámbar. La
    // señal pasa a luminancia y sale del color del fósforo; va después del
    // bloom (que sangra con el `tint`, que acá ya es el color del fósforo).
    col = mix(col, vec3(dot(col, vec3(0.299, 0.587, 0.114))) * monoTint, mono);

    vec2 fc = uv * res;

    // scanlines (tanda 8): one dark row every other row, on the rows of the
    // SCREEN and not of the tube. The period is two pixels, which is Nyquist
    // exactly: laid on the curved face, any stretch pushed it past what the
    // pixels can hold and it aliased — the beat against the grid goes as
    // `x²·y`, and that was the star over the middle of the screen and the
    // circles in the corners. Bent, the rows now stay straight, which at two
    // pixels nobody can see; flat, the comb is where it always was.
    //
    // And it holds still. It used to carry `+ t·1.6` so it would crawl, but a
    // two-pixel comb cannot crawl: the phase only turned its CONTRAST up and
    // down, the whole screen at once, every two seconds — and through the
    // curvature, the figures of the moiré came and went with it. The contrast
    // is now the average of that breathing (0.30 of 0.50), which also takes it
    // down a notch: Ferox found it too marked.
    float sy = qt_TexCoord0.y * res.y;
    float sl = 0.5 + 0.30 * cos(sy * 3.14159265);
    col *= 1.0 - scanline * 0.55 * sl;

    // La máscara del vidrio: RGB triads, the reason CRT text never looks clean.
    // Tres tubos distintos (`maskType`): la rejilla de apertura de siempre
    // (Trinitron: franjas verticales continuas), la slot mask de las arcade
    // (franjas cortadas en ranuras, ladrilladas) y la shadow mask de puntos de
    // un PVM (tríadas en delta, círculos).
    //
    // Tanda 8: la máscara va LIMITADA EN BANDA. Antes cada tríada era un
    // escalón (tres franjas de bordes duros, ranuras con un puente de un píxel,
    // puntos recortados), y un borde duro tiene armónicos por encima de lo que
    // la grilla de píxeles aguanta: a través de la curvatura eso se veía como
    // círculos en las esquinas. Ahora cada patrón es su fundamental (y el
    // segundo armónico del puente de la slot), escrito como cosenos, y cada
    // coseno se funde con `keepAt` según la frecuencia a la que cae EN
    // PANTALLA. El promedio de cada canal es el de antes, así que el brillo no
    // se mueve. El tipo 0 con pitch 3 en un tubo plano da, en el centro de cada
    // píxel, EXACTAMENTE 1.16 / 0.86 / 0.86 como antes.
    const float TAU = 6.2831853;
    // la fase de cada canal: R, G y B centrados en su tercio de la tríada
    const vec3 chPhase = vec3(0.5, 1.5, 2.5) * (TAU / 3.0);
    float fx = kx / maskPitch;
    vec3 mask;
    if (maskType < 0.5) {
        float ph = TAU * fc.x / maskPitch;
        mask = 0.96 + 0.20 * keepAt(fx) * cos(ph - chPhase);
    } else if (maskType < 1.5) {
        // slot: cada fila de ranuras mide dos tríadas de alto y se corre media
        // tríada respecto de la de arriba. Correr media tríada es cambiarle el
        // signo al coseno, así que las filas ladrilladas son el producto por un
        // coseno de media frecuencia en y (cero en el puente, ±1 en el centro
        // de la ranura): dos cosenos inclinados, sin escalón entre filas.
        float cy = fc.y / (maskPitch * 2.0);
        float fy = ky / (maskPitch * 2.0);
        float ph = TAU * fc.x / maskPitch;
        float rowSign = cos(3.14159265 * (cy - 0.422));
        mask = 0.96 + 0.26 * keepAt(fx) * rowSign * cos(ph - chPhase);
        // el puente oscuro entre ranuras: sus dos primeros armónicos, con el
        // promedio del de antes (0.943) y el centro donde estaba (0.922)
        float vb = cy - 0.922;
        mask *= 0.943 - 0.109 * keepAt(fy) * cos(TAU * vb)
                      - 0.094 * keepAt(2.0 * fy) * cos(2.0 * TAU * vb);
    } else {
        // puntos: cada canal es una red triangular de paso `maskPitch` (filas
        // de 0.866 de tríada, las impares corridas media tríada), y una red
        // triangular limitada en banda es la suma de tres cosenos a 120°. El
        // punto rojo, el verde y el azul se corren un tercio de tríada entre
        // sí. Promedio 0.82, el de los puntos de antes.
        vec2 q = fc / maskPitch;
        vec2 g1 = vec2(1.0, -0.57735);
        vec2 g2 = vec2(0.0, 1.1547);
        vec2 g3 = vec2(1.0, 0.57735);
        // centro del punto de cada canal (en tríadas): medio renglón abajo y su tercio
        vec3 ox = vec3(0.5, 1.5, 2.5) / 3.0;
        const float oy = 0.433;
        vec3 dots = vec3(0.0);
        dots += cos(TAU * (g1.x * (q.x - ox) + g1.y * (q.y - oy)));
        dots += cos(TAU * (g2.x * (q.x - ox) + g2.y * (q.y - oy)));
        dots += cos(TAU * (g3.x * (q.x - ox) + g3.y * (q.y - oy)));
        // la frecuencia en pantalla de la red: 1.15 tríadas⁻¹ en la peor dirección
        float fd = 1.1547 * max(kx, ky) / maskPitch;
        mask = 0.82 + 0.13 * keepAt(fd) * dots;   // dots va de -1.5 a 3
    }
    // un tubo monocromo tiene un solo fósforo: no hay tríadas
    col *= mix(vec3(1.0), mask, 0.55 * (1.0 - mono));

    // The interlaced entrance (T3.1): a tube fed a half frame draws every
    // other scanline and leaves the rest dark, and the picture only settles
    // once both fields land. It rides on top of the grille, over the whole
    // image and not just the glyph: what is half-drawn is the SIGNAL.
    if (interlacePhase > 0.5) {
        // en las filas de la pantalla, como las scanlines: de a una fila es
        // Nyquist y sobre la cara curva dibujaba el mismo moiré (tanda 8)
        float odd = mod(floor(sy), 2.0);
        float keep = interlacePhase < 1.5 ? 1.0 - odd : odd;
        col *= mix(0.10, 1.0, keep);
    }

    // The corridor of a jump used to live here: a band of scanlines crossing
    // the middle of the screen. It is `HopRay.qml` now (T3.B4) — the ray has to
    // have a head, a tail, a gradient and a route that goes around the motif by
    // the EDGE, and none of that fits in a band riding the comb.

    // rolling bar: the classic bright band sliding down an out-of-sync tube
    float by = rollPhase;
    float d = abs(fract(uv.y - by + 0.5) - 0.5);
    col += tint * 0.05 * smoothstep(0.07, 0.0, d) * roll;

    // el tubo apagado: la señal se contrae a nada, y el ruido de fósforo (más
    // abajo) queda solo, no multiplicado por esto — es lo que se ve cuando NO
    // hay señal, no una señal a media luz.
    col *= tubeLevel;

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
    // el escalón al azar 24 veces por segundo es lo que hace que un tubo parezca
    // vivo, pero de más se lee como una lámpara que falla: va bajito
    col *= 1.0 - 0.022 * sin(t * 377.0) - 0.010 * hash11(floor(t * 24.0));
    col *= 1.0 + pulse * (0.10 + 0.10 * hash11(floor(t * 11.0)));
    // y en los picos, el apagón corto de una tele a la que le falta corriente
    col *= 1.0 - blink * 0.55;

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
