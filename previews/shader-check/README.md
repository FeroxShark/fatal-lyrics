# Banco del vidrio y del túnel (tanda 8)

Rinde `shell/crt.frag.qsb` sobre un campo parejo (donde el moiré no tiene dónde esconderse) y sobre el
túnel quieto, y `shell/tunnel.frag.qsb` pelado, a 1920×1080 y 1080×1920. Nunca abre nada en pantalla.

```
./render.py --dir ../../shell --tag despues     # out/despues/*.png + metrics.json
./render.py --dir /tmp/qsb-viejos --tag antes   # el antes: una copia de los .qsb anteriores
./moire_map.py out/despues/glass-arcade-1920x1080.png   # la figura, contraste estirado
```

Métricas (`render.py`): `envolvente` (cuánto varía a gran escala el contraste de la textura fina — es
lo que el ojo ve como estrella/círculos), `moire` (brillo entre 8 y 200 px), `textura` (lo que queda de
la máscara/scanlines: que no se vaya a cero) y la costura del túnel.
