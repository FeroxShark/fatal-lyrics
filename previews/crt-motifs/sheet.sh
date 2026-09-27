#!/bin/sh
# ./sheet.sh <kind> <t1,t2,t3,t4> [render.py args...] → out/sheet-<kind>.png (2×2)
# Para revisar un motivo a ojo sin renderizar el loop entero.
set -e
cd "$(dirname "$0")"
k=$1; ts=$2; shift 2
./render.py "$k" --stills "$ts" "$@" 2>&1 | grep -v '^  ' | grep -v '\.png$' || true
set -- $(echo "$ts" | tr ',' ' ')
f() { printf 'out/stills/%s-t%06.3f.png' "$k" "$1"; }
ffmpeg -y -loglevel error -i "$(f $1)" -i "$(f $2)" -i "$(f $3)" -i "$(f $4)" \
  -filter_complex "[0][1][2][3]xstack=inputs=4:layout=0_0|w0_0|0_h0|w0_h0,scale=1920:-1" "out/sheet-$k.png"
echo "out/sheet-$k.png"
