#!/bin/sh
# Copia de shell/ al banco lo que el laberinto necesita (imports "../X.js"):
#   ./sync-shell.sh          # MotifBase, ThumpBase, Maze, Mystify, Membrana, Cintas, Giroscopio, Dunes, Ocean, Pond, sus shaders (.qsb), Maze.js, Dots.js, Mystify.js, React.js, Speed.js, Thump.js
# shell/ es la fuente: se edita ahí y se corre esto antes de renderizar.
set -e
cd "$(dirname "$0")"
S=../../shell
for f in Maze Mystify Swarm MotifBase ThumpBase Membrana Cintas Giroscopio Dunes Ocean Pond; do
  # `Motion` es un singleton de shell/ (qmldir): en el banco va su valor (levelMs = 420)
  sed -e 's#import "\([A-Za-z]*\)\.js"#import "../\1.js"#' -e 's#Motion\.levelMs#420#' "$S/$f.qml" > "motifs/$f.qml"
done
cp "$S/dunes.frag" "$S/dunes.frag.qsb" "$S/ocean.frag" "$S/ocean.frag.qsb" "$S/pond.frag" "$S/pond.frag.qsb" "$S/membrana.frag" "$S/membrana.frag.qsb" "$S/cintas.frag" "$S/cintas.frag.qsb" "$S/giroscopio.frag" "$S/giroscopio.frag.qsb" "$S/maze.frag" "$S/maze.frag.qsb" "$S/mystify.frag" "$S/mystify.frag.qsb" "$S/swarm.vert" "$S/swarm.vert.qsb" "$S/swarm.frag" "$S/swarm.frag.qsb" motifs/
cp "$S/Maze.js" "$S/Mystify.js" "$S/React.js" "$S/Speed.js" "$S/Thump.js" .
