local startup_commands = {
    "awww-daemon",
    "~/.local/share/hyprarch/shell/wallpaper.sh theme && sleep 1 && hyprlock",
    "quickshell -n -p ~/.local/share/hyprarch/quickshell",
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
