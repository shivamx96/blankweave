-- Stable action IDs let Settings change keys without replacing dispatchers or flags.
_G.blankweave_shortcuts_revision = "defaults"
local saved = {}
local path = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config"))
    .. "/blankweave/shortcuts.lua"
local file, message, code = io.open(path, "r")
if file then
    file:close()
    saved = dofile(path)
    assert(type(saved) == "table", "Invalid saved shortcuts")
elseif code ~= 2 then
    error(message)
end
local function bind(id, default, action, options)
    options = options or {}
    options.description = "blankweave:" .. id
    hl.bind(saved[id] or default, action, options)
end

local main_mod = "SUPER"

-- Applications
bind("settings", main_mod .. " + comma", hl.dsp.exec_cmd("~/.local/bin/blankweave settings"))
bind("terminal", main_mod .. " + Return", hl.dsp.exec_cmd("ghostty"))
bind("browser", main_mod .. " + B", hl.dsp.exec_cmd("zen-browser"))
bind("bluetooth", main_mod .. " + SHIFT + B", hl.dsp.exec_cmd("blueman-manager"))
bind("files", main_mod .. " + F", hl.dsp.exec_cmd("thunar"))
bind("launcher", main_mod .. " + space", hl.dsp.exec_cmd([[qs ipc -n -p "$HOME/.local/share/blankweave/quickshell" call blankweave launcher]]))
bind("lock", main_mod .. " + L", hl.dsp.exec_cmd("hyprlock"))
bind("theme", main_mod .. " + T", hl.dsp.exec_cmd("~/.local/share/blankweave/shell/theme-apply.sh toggle"))
bind("wallpaper", main_mod .. " + SHIFT + W", hl.dsp.exec_cmd("~/.local/share/blankweave/shell/wallpaper.sh cycle"))
bind("clipboard", main_mod .. " + SHIFT + V", hl.dsp.exec_cmd([[qs ipc -n -p "$HOME/.local/share/blankweave/quickshell" call blankweave clipboard]]))
bind("reload-shell", main_mod .. " + Y", hl.dsp.exec_cmd([[qs ipc -n -p "$HOME/.local/share/blankweave/quickshell" call blankweave reload]]))

-- Screenshots
bind("screenshot-print", "Print", hl.dsp.exec_cmd("grim - | wl-copy"))
bind("screenshot", main_mod .. " + S", hl.dsp.exec_cmd("grim - | wl-copy"))
bind("screenshot-region", main_mod .. " + SHIFT + S", hl.dsp.exec_cmd([[grim -g "$(slurp)" - | wl-copy]]))

-- Multimedia keys (repeating = repeat on hold)
bind("volume-up", "XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+ && ~/.local/share/blankweave/shell/volume-popup.sh"), { repeating = true })
bind("volume-down", "XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- && ~/.local/share/blankweave/shell/volume-popup.sh"), { repeating = true })
bind("volume-mute", "XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && ~/.local/share/blankweave/shell/volume-popup.sh"))
bind("media-play", "XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"))
bind("media-pause", "XF86AudioPause", hl.dsp.exec_cmd("playerctl pause"))
bind("media-next", "XF86AudioNext", hl.dsp.exec_cmd("playerctl next"))
bind("media-previous", "XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"))
bind("brightness-up", "XF86MonBrightnessUp", hl.dsp.exec_cmd("~/.local/share/blankweave/shell/brightness.sh up 5"), { repeating = true })
bind("brightness-down", "XF86MonBrightnessDown", hl.dsp.exec_cmd("~/.local/share/blankweave/shell/brightness.sh down 5"), { repeating = true })

-- Window management
bind("close-window", main_mod .. " + Q", hl.dsp.window.close())
bind("float-window", main_mod .. " + V", hl.dsp.window.float({ action = "toggle" }))
bind("pseudo-window", main_mod .. " + P", hl.dsp.window.pseudo({ action = "toggle" }))
bind("split", main_mod .. " + J", hl.dsp.layout("togglesplit"))
bind("logout", main_mod .. " + M", hl.dsp.exec_cmd("uwsm stop"))

-- Focus with arrow keys
bind("focus-left", main_mod .. " + left", hl.dsp.focus({ direction = "l" }))
bind("focus-right", main_mod .. " + right", hl.dsp.focus({ direction = "r" }))
bind("focus-up", main_mod .. " + up", hl.dsp.focus({ direction = "u" }))
bind("focus-down", main_mod .. " + down", hl.dsp.focus({ direction = "d" }))

-- Move window to monitor
bind("move-monitor", main_mod .. " + SHIFT + K", hl.dsp.window.move({ monitor = "+1" }))

-- Scroll workspaces
bind("workspace-next", main_mod .. " + CTRL + right", hl.dsp.focus({ workspace = "e+1" }))
bind("workspace-previous", main_mod .. " + CTRL + left", hl.dsp.focus({ workspace = "e-1" }))

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
    bind("workspace-" .. workspace, main_mod .. " + " .. key, summon_workspace(workspace))
    bind("move-workspace-" .. workspace, main_mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = workspace }))
end

-- Assistive tool shortcuts are included in the editable shortcut catalog.
bind("assistive-reader", "SUPER + CTRL + R", hl.dsp.exec_cmd("python3 ~/.local/share/blankweave/shell/settings_session.py reader"))
bind("assistive-keyboard", "SUPER + CTRL + K", hl.dsp.exec_cmd("python3 ~/.local/share/blankweave/shell/settings_session.py keyboard"))
bind("assistive-zoom-reset", "SUPER + CTRL + M", hl.dsp.exec_cmd("python3 ~/.local/share/blankweave/shell/settings_session.py zoom"))
