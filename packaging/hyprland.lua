-- fatal-lyrics para Hyprland 0.56+ (config en Lua). Reemplaza las líneas de hyprlang de antes
-- (`exec-once` en execs.conf, `bind =` en keybinds.conf), que el parser de Lua ya no lee.
-- Se carga desde ~/.config/hypr/hyprland.lua con:
--     local fl = os.getenv("HOME") .. "/cartelitos/packaging/hyprland.lua"
--     if io.open(fl) then dofile(fl) end
--
-- El binario es el que deja install.sh, ~/.local/bin/fatal (symlink al bin/fatal del repo), o el
-- del paquete, /usr/bin/fatal. Va con ruta absoluta: el exec de Hyprland no siempre tiene
-- ~/.local/bin en el PATH.
--
-- Reglas de ventana no hacen falta: todo lo que dibuja fatal-lyrics son capas layer-shell en
-- Overlay (namespaces cartelitos, cartelitos-np, cartelitos-crt, cartelitos-tune), sin foco
-- ni zona exclusiva, y cada una se pone sola en su monitor.

local FATAL = os.getenv("HOME") .. "/.local/bin/fatal"
if not io.open(FATAL) then FATAL = "/usr/bin/fatal" end

-- Las capas de Hyprland están animadas (layersIn/fadeLayers): sin esto cada cartel entraría con
-- el slide/fade del compositor encima de la entrada propia (shell/Motion.qml) — dos movimientos
-- a la vez. 0.56 compara el namespace ENTERO: va "^cartelitos.*$", no "^cartelitos".
hl.layer_rule({ name = "fatal-lyrics", match = { namespace = "^cartelitos.*$" }, no_anim = true })

-- Autostart: UNO solo (docs/TRAMPAS.md, "Autostart: un solo exec-once"). El sleep es para que
-- los monitores ya estén; `restart` deja estado limpio aunque haya quedado media instancia.
hl.on("hyprland.start", function()
    hl.exec_cmd("sh -c 'sleep 6 && " .. FATAL .. " restart'")
end)

-- Interruptor del CRT. La salida que nunca depende del overlay (README, "CRT mode"). Igual que
-- las del sync: tiene que ser la de [keys] crt_toggle de fábrica ("Super+Shift, Y"), que es
-- además la que la letra muestra escrita al empezar cada tema.
hl.bind("SUPER + SHIFT + Y", hl.dsp.exec_cmd(FATAL .. " crt toggle"))

-- Sync fino ±0.1 s. Tienen que ser las mismas que [keys] de fábrica ("Super+Alt, Right/Left"):
-- mientras la perilla no cambie, el daemon no toca estos binds. Super+Shift+flechas ya mueve
-- ventanas (docs/TRAMPAS.md).
hl.bind("SUPER + ALT + Right", hl.dsp.exec_cmd(FATAL .. " sync +"))
hl.bind("SUPER + ALT + Left",  hl.dsp.exec_cmd(FATAL .. " sync -"))
