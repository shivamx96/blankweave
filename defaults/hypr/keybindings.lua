local main_mod = "SUPER"

-- Applications
hl.bind(main_mod .. " + Return", hl.dsp.exec_cmd("ghostty"))
hl.bind(main_mod .. " + B", hl.dsp.exec_cmd("zen-browser"))
hl.bind(main_mod .. " + SHIFT + B", hl.dsp.exec_cmd("blueman-manager"))
hl.bind(main_mod .. " + F", hl.dsp.exec_cmd("thunar"))
hl.bind(main_mod .. " + space", hl.dsp.exec_cmd([[qs ipc -n -p "$HOME/.local/share/blankweave/quickshell" call blankweave launcher]]))
hl.bind(main_mod .. " + L", hl.dsp.exec_cmd("hyprlock"))
hl.bind(main_mod .. " + D", hl.dsp.exec_cmd("~/.local/share/blankweave/shell/theme-apply.sh toggle"))
hl.bind(main_mod .. " + SHIFT + W", hl.dsp.exec_cmd("~/.local/share/blankweave/shell/wallpaper.sh cycle"))
hl.bind(main_mod .. " + SHIFT + V", hl.dsp.exec_cmd([[qs ipc -n -p "$HOME/.local/share/blankweave/quickshell" call blankweave clipboard]]))
hl.bind(main_mod .. " + Y", hl.dsp.exec_cmd([[qs ipc -n -p "$HOME/.local/share/blankweave/quickshell" call blankweave reload]]))

-- Screenshots
hl.bind("Print", hl.dsp.exec_cmd("grim - | wl-copy"))
hl.bind(main_mod .. " + S", hl.dsp.exec_cmd("grim - | wl-copy"))
hl.bind(main_mod .. " + SHIFT + S", hl.dsp.exec_cmd([[grim -g "$(slurp)" - | wl-copy]]))

-- Multimedia keys (repeating = repeat on hold)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+ && ~/.local/share/blankweave/shell/volume-popup.sh"), { repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- && ~/.local/share/blankweave/shell/volume-popup.sh"), { repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && ~/.local/share/blankweave/shell/volume-popup.sh"))
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl pause"))
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"))
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"))
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("~/.local/share/blankweave/shell/brightness.sh up 5"), { repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("~/.local/share/blankweave/shell/brightness.sh down 5"), { repeating = true })

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

-- Workspaces are not bound to monitors. Super+N brings workspace N to the
-- focused monitor (swapping with whatever it was showing) instead of moving
-- focus to wherever N happens to live, and pressing it again while N is
-- already there sends N on to the next monitor, so repeated presses cycle a
-- workspace through the displays. The bar's workspace buttons do the same.
local function summon_workspace(workspace)
    return function()
        local monitor = hl.get_active_monitor()
        local active = monitor and monitor.active_workspace
        if active and active.id == workspace and #hl.get_monitors() > 1 then
            hl.dispatch(hl.dsp.workspace.move({ monitor = "+1" }))
        else
            hl.dispatch(hl.dsp.focus({ workspace = workspace, on_current_monitor = true }))
        end
    end
end

-- Switch workspaces and move windows to workspaces. Workspace 10 maps to key 0.
for workspace = 1, 10 do
    local key = workspace % 10
    hl.bind(main_mod .. " + " .. key, summon_workspace(workspace))
    hl.bind(main_mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = workspace }))
end
