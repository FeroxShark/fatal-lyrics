#!/bin/sh
# sheet.sh OUT.png COLS a.png b.png ... — hoja de cuadros para revisar a ojo
out=$1; cols=$2; shift 2
magick "$@" -resize 640x360 -bordercolor '#222' -border 4 miff:- | magick montage - -tile "${cols}x" -geometry +0+0 -background '#222' "$out"
