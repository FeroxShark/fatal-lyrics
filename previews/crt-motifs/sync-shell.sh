#!/bin/sh
# Copia de shell/ al banco lo que el laberinto necesita (imports "../X.js"):
#   ./sync-shell.sh          # MotifBase, ThumpBase, Maze, Mystify, Membrana, Cintas, Giroscopio, sus shaders (.qsb), Maze.js, Mystify.js, React.js, Speed.js, Thump.js
# shell/ es la fuente: se edita ahí y se corre esto antes de renderizar.
set -e
cd "$(dirname "$0")"
S=../../shell
for f in Maze Mystify MotifBase ThumpBase Membrana Cintas Giroscopio; do
  sed -e 's#import "\([A-Za-z]*\)\.js"#import "../\1.js"#' "$S/$f.qml" > "motifs/$f.qml"
done
cp "$S/membrana.frag" "$S/membrana.frag.qsb" "$S/cintas.frag" "$S/cintas.frag.qsb" "$S/giroscopio.frag" "$S/giroscopio.frag.qsb" "$S/maze.frag" "$S/maze.frag.qsb" "$S/mystify.frag" "$S/mystify.frag.qsb" motifs/
cp "$S/Maze.js" "$S/Mystify.js" "$S/React.js" "$S/Speed.js" "$S/Thump.js" .
