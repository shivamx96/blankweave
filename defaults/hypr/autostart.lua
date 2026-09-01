local startup_commands = {
    "awww-daemon",
    "~/.local/share/blankweave/shell/wallpaper.sh theme",
    "quickshell -n -p ~/.local/share/blankweave/quickshell",
    "dunst",
    "hypridle",
    "wl-paste --type text --watch cliphist store",
    "wl-paste --type image --watch cliphist store",
    "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1",
}

hl.on("hyprland.start", function()
    for _, command in ipairs(startup_commands) do
        hl.exec_cmd(command)
    end
end)

-- A monitor that appears after startup has no wallpaper: awww only paints
-- the outputs that exist when `img` runs, so repaint the newcomer. The
-- callback receives the compositor's monitor object; only its connector
-- name is needed, and it is validated before reaching a shell command line.
hl.on("monitor.added", function(monitor)
    local name = monitor and monitor.name
    if type(name) ~= "string" or not name:match("^[%w%-]+$") then
        return
    end
    hl.exec_cmd("~/.local/share/blankweave/shell/wallpaper.sh restore " .. name)
end)
