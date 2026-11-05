#version 440
// fatal-lyrics — la rejilla de los instrumentos (`scope`, `ekg`): cuadrito, grueso cada `major`,
// marco y, si `axes`, los ejes centrales con sus marquitas. Sale transparente: va sobre la cara.
//
// Build:  /usr/lib/qt6/bin/qsb --glsl '100 es,120,150' -o scopegrid.frag.qsb scopegrid.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 ink;
    vec2 res;
    float cell;    // px del cuadrito
    float major;   // cada cuántos, el grueso
    float axes;    // 1 = ejes centrales con marcas
    float gain;
};

float line(float d, float w) { return smoothstep(w + 0.7, w - 0.3, d); }

void main() {
    vec2 p = qt_TexCoord0 * res;
    vec2 c = p - res * 0.5;
    // la grilla sale del centro: las líneas de los bordes quedan parejas
    vec2 g = abs(fract(c / cell + 0.5) - 0.5) * cell;
    vec2 gm = abs(fract(c / (cell * major) + 0.5) - 0.5) * cell * major;
    float a = max(line(g.x, 0.5), line(g.y, 0.5)) * 0.07;
    a = max(a, max(line(gm.x, 0.7), line(gm.y, 0.7)) * 0.20);
    if (axes > 0.5) {
        float ax = max(line(abs(c.x), 0.8), line(abs(c.y), 0.8)) * 0.42;
        float mk = cell * 0.22;
        float ticks = max(line(g.y, 0.8) * step(abs(c.x), mk), line(g.x, 0.8) * step(abs(c.y), mk));
        a = max(a, max(ax, ticks * 0.7));
    }
    vec2 e = min(p, res - p);
    a = max(a, line(min(e.x, e.y), 1.0) * 0.65);
    a *= gain * qt_Opacity;
    fragColor = vec4(ink.rgb * a, a);
}
