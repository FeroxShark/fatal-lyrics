#version 440
// fatal-lyrics — motivo `pixelsort` (2026-10-22): glitch art de verdad. Una pila de ventanas
// de error (rectángulos con barra de título) se ORDENA por brillo, columna por columna: los
// tramos de cada columna cuyo brillo cae dentro del umbral se reordenan de oscuro a claro y
// la ventana se chorrea hacia abajo en rayas, como el pixel-sort de los GIF de glitch.
//
// Todo analítico por píxel, sin texturas. La columna se parte en CELDAS de alto fijo y en
// TRAMOS de 12 celdas (con arranque distinto por columna, así los cortes no hacen una línea);
// dentro de un tramo, las celdas con brillo en [lo, hi] forman una corrida contigua, y la
// celda `r` de la corrida muestra la `r`-ésima más oscura. El brillo entre celdas se
// interpola con la siguiente, así el degradado es continuo.
//   · el bombo (`pulse`, la envolvente del resorte de Thump.js) ABRE el umbral: más ventana
//     entra al orden y los chorros se hacen largos; después se cierra con el mismo resorte
//   · el compás (`bn`, `since`, `beatS`): cada ventana salta a otro lugar con el snap de
//     Motion (OutExpo 320 ms) en una vuelta de 2 tiempos, escalonadas: en cada tiempo se
//     mueven una o dos, no todas
//   · agudos (`fizz`): columnas sueltas que chispean
//   · densidad (`dens`): baja el umbral de abajo (más de la imagen se ordena)
//
// Build:  /usr/lib/qt6/bin/qsb --glsl '100 es,120,150' -o pixelsort.frag.qsb pixelsort.frag

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
    float beatS;      // s por tiempo
    float seed;
    float dropAmt;    // 0..1
    float quality;    // 0.5..1
};

const int N = 14;                 // celdas por tramo
const int RECTS = 8;

float h11(float n) { return fract(sin(n * 12.9898 + 4.1414) * 43758.5453); }
float h21(vec2 p) { return h11(p.x * 57.0 + p.y * 131.0); }
float outExpo(float x) { return x >= 1.0 ? 1.0 : 1.0 - exp2(-10.0 * x); }

// brillo de la imagen de origen en `p` (0..1 en x, y en unidades de alto/ancho: aspecto real)
float src(vec2 p, float asp) {
    float l = 0.07 + 0.05 * h11(floor(p.y * 90.0) + seed * 3.0);      // fondo con renglones
    for (int i = 0; i < RECTS; i++) {
        float fi = float(i);
        float L = floor((bn + fi) * 0.5);                              // cada una se mueve cada 2 tiempos
        float age = (mod(bn + fi, 2.0)) * beatS + since;
        float k = outExpo(clamp(age / 0.32, 0.0, 1.0));
        vec2 c0 = vec2(0.14 + 0.72 * h21(vec2(L - 1.0, fi + seed * 7.0)),
                       0.12 + 0.76 * h21(vec2(L - 1.0, fi + 40.0 + seed * 7.0)));
        vec2 c1 = vec2(0.14 + 0.72 * h21(vec2(L, fi + seed * 7.0)),
                       0.12 + 0.76 * h21(vec2(L, fi + 40.0 + seed * 7.0)));
        vec2 c = mix(c0, c1, k) + 0.012 * vec2(sin(drift * 0.7 + fi * 2.1), cos(drift * 0.5 + fi * 1.3));
        vec2 sz = vec2(0.10 + 0.10 * h11(fi * 3.7 + seed), 0.07 + 0.07 * h11(fi * 5.3 + seed + 9.0));
        vec2 d = abs(vec2(p.x - c.x, (p.y - c.y) / asp)) - sz;
        if (d.x < 0.0 && d.y < 0.0) {
            float v = 0.40 + 0.60 * h11(fi * 1.9 + 2.0 + seed);
            float u = (p.y - c.y) / asp / sz.y;                         // -1 arriba .. 1 abajo (en y de pantalla)
            float ux = (p.x - c.x) / sz.x;                              // -1 izquierda .. 1 derecha
            float bar = u < -0.70 ? 1.15 : 1.0;                         // la barra de título, más clara
            float grad = 0.78 + 0.22 * (0.5 - 0.5 * ux);
            // renglones de texto de largo distinto: contraste para que el orden tenga qué mover
            float row = floor((u + 1.0) * 4.5);
            float txt = (u > -0.62 && ux < -0.8 + 1.6 * h21(vec2(row, fi + seed * 3.0))) ? 0.55 + 0.45 * h21(vec2(row + 9.0, fi)) : 0.32;
            bool edge = abs(ux) > 0.955 || abs(u) > 0.93;               // el marco, más claro
            float lv = v * bar * grad * (u < -0.70 ? 1.0 : txt * 1.5);
            l = max(l, edge ? v * 1.25 : lv);
        }
    }
    return l;
}

void main() {
    vec2 px = qt_TexCoord0 * res;
    float asp = res.x / res.y;
    float cw = max(3.0, res.x / (300.0 * quality));               // ancho de columna (px)
    float ch = res.y / 80.0;                                      // alto de celda (px)
    float colId = floor(px.x / cw);
    float xc = (colId + 0.5) * cw / res.x;
    // el arranque de los tramos cambia por columna: los cortes no forman una línea
    float off = floor(h11(colId + seed * 11.0) * float(N));
    float cy = floor(px.y / ch) + off;
    float chunk = floor(cy / float(N));
    int c = int(cy - chunk * float(N));                            // celda dentro del tramo (0..N-1)
    float y0 = (chunk * float(N) - off) * ch;                      // arriba del tramo (px)

    // el umbral: el golpe lo abre, la densidad lo baja, la deriva lo mueve aunque no suene nada
    float lo = 0.36 - 0.20 * pulse - 0.10 * dens + 0.05 * sin(drift * 0.4);
    float hi = 0.90 + 0.10 * pulse;
    // un par de columnas más finas o más gruesas por tramo: no todas se ordenan igual
    float wob = h21(vec2(colId, chunk + seed)) ;
    lo += 0.10 * (wob - 0.5);

    float Ls[N];
    float ok[N];
    for (int k = 0; k < N; k++) {
        float yy = (y0 + (float(k) + 0.5) * ch) / res.y;
        float l = src(vec2(xc, yy), asp);
        Ls[k] = l;
        ok[k] = (l >= lo && l <= hi) ? 1.0 : 0.0;
    }

    float own = 0.0, nxt = 0.0;
    float fy = fract(px.y / ch);
    // ¿esta celda está dentro de una corrida?
    float okc = 0.0;
    for (int k = 0; k < N; k++) if (k == c) { okc = ok[k]; own = Ls[k]; }
    float l = own;
    if (okc > 0.5) {
        int s = 0, e = N - 1;
        bool found = false;
        for (int k = 0; k < N; k++) {
            if (k <= c && ok[k] < 0.5) s = k + 1;
            if (k > c && ok[k] < 0.5 && !found) { e = k - 1; found = true; }
        }
        int r = c - s;
        float v0 = own, v1 = own;
        for (int k = 0; k < N; k++) {
            if (k < s || k > e) continue;
            int cnt = 0;
            for (int m = 0; m < N; m++) {
                if (m < s || m > e) continue;
                if (Ls[m] < Ls[k] || (Ls[m] == Ls[k] && m < k)) cnt++;
            }
            if (cnt == r) v0 = Ls[k];
            if (cnt == r + 1) v1 = Ls[k];
        }
        if (c == e) v1 = v0;
        l = mix(v0, v1, fy);
    } else {
        // fuera de la corrida: la imagen tal cual, a la altura exacta del píxel
        l = src(vec2(xc, px.y / res.y), asp);
    }

    // agudos: columnas sueltas que chispean
    float sp = step(0.965, h11(colId * 1.7 + floor(drift * 3.0))) * fizz;
    l = clamp(l + 0.35 * sp, 0.0, 1.2);

    // rampa de fósforo: fondo → tinta → luz
    vec3 col = mix(bg.rgb, ink.rgb, smoothstep(0.05, 0.62, l));
    col = mix(col, hot.rgb, smoothstep(0.70, 1.05, l));
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
