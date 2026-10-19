// fatal-lyrics — cómo se reparte una línea larga en renglones centrados (modo CRT, allMode).
//
// Hasta ahora la letra entera se medía con UNA palabra por renglón: el `Text.Fit` llenaba la
// altura y una línea de 12 palabras quedaba a ~84 px en una pantalla de 1080. Acá se elige
// cuántos renglones conviene y qué palabras caen en cada uno; el tamaño final lo sigue
// poniendo el `Text.Fit` de `Crt.qml` sobre esos renglones (así no puede desbordar).
//
// PURO: sin Qt. Las cuentas de abajo son una estimación para ELEGIR el reparto (el ancho de
// un glifo de la fuente se supone `cw` em); el tamaño real sale del `Text.Fit`.
.pragma library

// Tamaño estimado (px) de la letra con `r` renglones de a lo sumo `maxChars` caracteres.
function estimate(r, maxChars, boxW, boxH, maxPx, cw, lineH) {
    return Math.min(maxPx, boxH / (r * lineH), boxW / (Math.max(maxChars, 1) * cw));
}

// Reparte los índices 0..n-1 en renglones consecutivos de a lo sumo `cap` caracteres (contando el
// espacio entre palabras), con el menor número de renglones posible y, entre esos, lo más
// parejos que se pueda (mínima suma de cuadrados): el codicioso solo deja un renglón de una
// palabra colgando. Devuelve { rows, maxChars }.
function split(words, r) {
    const n = words.length;
    const lens = words.map(w => Array.from(w).length);
    r = Math.max(1, Math.min(r, n));
    const span = (a, b) => {          // caracteres de las palabras a..b-1 en un renglón
        let c = b - a - 1;
        for (let i = a; i < b; i++)
            c += lens[i];
        return c;
    };
    // tope más chico con el que n palabras entran en r renglones (búsqueda binaria)
    const needs = cap => {
        let rows = 1;
        let cur = -1;
        for (let i = 0; i < n; i++) {
            if (cur >= 0 && cur + 1 + lens[i] > cap) {
                rows++;
                cur = lens[i];
            } else {
                cur = cur < 0 ? lens[i] : cur + 1 + lens[i];
            }
        }
        return rows;
    };
    let lo = Math.max.apply(null, lens);
    let hi = span(0, n);
    while (lo < hi) {
        const mid = (lo + hi) >> 1;
        if (needs(mid) <= r)
            hi = mid;
        else
            lo = mid + 1;
    }
    const cap = lo;
    const k = needs(cap);
    // k renglones exactos, ninguno pasa de `cap`, mínima suma de cuadrados
    const INF = 1e18;
    const cost = [];
    const cut = [];
    for (let j = 0; j <= k; j++) {
        cost.push(new Array(n + 1).fill(INF));
        cut.push(new Array(n + 1).fill(0));
    }
    cost[0][0] = 0;
    for (let j = 1; j <= k; j++) {
        for (let i = j; i <= n; i++) {
            for (let a = j - 1; a < i; a++) {
                if (cost[j - 1][a] >= INF)
                    continue;
                const c = span(a, i);
                if (c > cap)
                    continue;
                const v = cost[j - 1][a] + c * c;
                if (v < cost[j][i]) {
                    cost[j][i] = v;
                    cut[j][i] = a;
                }
            }
        }
    }
    const rows = [];
    for (let j = k, i = n; j >= 1; j--) {
        const a = cut[j][i];
        const row = [];
        for (let q = a; q < i; q++)
            row.push(q);
        rows.unshift(row);
        i = a;
    }
    return { rows: rows, maxChars: cap };
}

// El reparto a usar. `gain`: cuánto más grande tiene que salir la letra (estimada) para
// abandonar el apilado de siempre — las líneas cortas, que ya llenan la pantalla apiladas,
// no cambian. Devuelve [[índices del renglón 0], [renglón 1], ...].
function pick(words, boxW, boxH, maxPx, cw, lineH, gain) {
    const n = words.length;
    const stacked = words.map((w, i) => [i]);
    if (n <= 2)
        return stacked;
    const lens = words.map(w => Array.from(w).length);
    const base = estimate(n, Math.max.apply(null, lens), boxW, boxH, maxPx, cw, lineH);
    let best = null;
    let bestPx = base * (gain === undefined ? 1.25 : gain);
    for (let r = 1; r < n; r++) {
        const s = split(words, r);
        const px = estimate(s.rows.length, s.maxChars, boxW, boxH, maxPx, cw, lineH);
        if (px > bestPx) {
            bestPx = px;
            best = s.rows;
        }
    }
    return best || stacked;
}
