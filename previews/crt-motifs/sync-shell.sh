#!/bin/sh
# Copia de shell/ al banco lo que el laberinto necesita (imports "../X.js"):
#   ./sync-shell.sh          # MotifBase, Maze, maze.frag(.qsb), Maze.js, Speed.js
# shell/ es la fuente: se edita ahí y se corre esto antes de renderizar.
set -e
cd "$(dirname "$0")"
S=../../shell
for f in Maze MotifBase; do
  sed -e 's#import "\([A-Za-z]*\)\.js"#import "../\1.js"#' "$S/$f.qml" > "motifs/$f.qml"
done
cp "$S/maze.frag" "$S/maze.frag.qsb" motifs/
cp "$S/Maze.js" "$S/Speed.js" .
