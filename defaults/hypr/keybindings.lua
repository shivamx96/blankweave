local main_mod = "SUPER"

-- Applications
hl.bind(main_mod .. " + Return", hl.dsp.exec_cmd("ghostty"))
hl.bind(main_mod .. " + B", hl.dsp.exec_cmd("zen-browser"))
hl.bind(main_mod .. " + SHIFT + B", hl.dsp.exec_cmd("blueman-manager"))
hl.bind(main_mod .. " + F", hl.dsp.exec_cmd("thunar"))
hl.bind(main_mod .. " + space", hl.dsp.exec_cmd([[qs ipc -n -p "$HOME/.local/share/hyprarch/quickshell" call hyprarch launcher]]))
hl.bind(main_mod .. " + SHIFT + space", hl.dsp.exec_cmd("fuzzel"))
hl.bind(main_mod .. " + L", hl.dsp.exec_cmd("hyprlock"))
hl.bind(main_mod .. " + D", hl.dsp.exec_cmd("~/.local/share/hyprarch/shell/theme-toggle.sh"))
hl.bind(main_mod .. " + SHIFT + W", hl.dsp.exec_cmd("~/.local/share/hyprarch/shell/wallpaper.sh cycle"))
hl.bind(main_mod .. " + SHIFT + V", hl.dsp.exec_cmd("cliphist list | fuzzel --dmenu | cliphist decode | wl-copy"))
hl.bind(main_mod .. " + Y", hl.dsp.exec_cmd([[qs ipc -n -p "$HOME/.local/share/hyprarch/quickshell" call hyprarch reload]]))

-- Screenshots
hl.bind("Print", hl.dsp.exec_cmd("grim - | wl-copy"))
hl.bind(main_mod .. " + S", hl.dsp.exec_cmd("grim - | wl-copy"))
hl.bind(main_mod .. " + SHIFT + S", hl.dsp.exec_cmd([[grim -g "$(slurp)" - | wl-copy]]))

-- Multimedia keys (repeating = repeat on hold)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+ && ~/.local/share/hyprarch/shell/volume-popup.sh"), { repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- && ~/.local/share/hyprarch/shell/volume-popup.sh"), { repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && ~/.local/share/hyprarch/shell/volume-popup.sh"))
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("~/.local/share/hyprarch/shell/brightness.sh up 5"), { repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("~/.local/share/hyprarch/shell/brightness.sh down 5"), { repeating = true })

-- Window management
hl.bind(main_mod .. " + Q", hl.dsp.window.close())
hl.bind(main_mod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(main_mod .. " + P", hl.dsp.window.pseudo({ action = "toggle" }))
hl.bind(main_mod .. " + J", hl.dsp.layout("togglesplit"))
hl.bind(main_mod .. " + M", hl.dsp.exec_cmd("uwsm stop"))

-- Focus with arrow keys
hl.bind(main_mod .. " + left", hl.dsp.focus({ direction = "l" }))
hl.bind(main_mod .. " + right", hl.dsp.focus({ direction = "r" }))
hl.bind(main_mod .. " + up", hl.dsp.focus({ direction = "u" }))
hl.bind(main_mod .. " + down", hl.dsp.focus({ direction = "d" }))

-- Move window to monitor
hl.bind(main_mod .. " + SHIFT + K", hl.dsp.window.move({ monitor = "+1" }))

-- Scroll workspaces
hl.bind(main_mod .. " + CTRL + right", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(main_mod .. " + CTRL + left", hl.dsp.focus({ workspace = "e-1" }))

-- Switch workspaces and move windows to workspaces. Workspace 10 maps to key 0.
for workspace = 1, 10 do
    local key = workspace % 10
    hl.bind(main_mod .. " + " .. key, hl.dsp.focus({ workspace = workspace }))
    hl.bind(main_mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = workspace }))
end
