local config_dir = os.getenv("HOME") .. "/.local/share/hyprarch/hypr/"

require(config_dir .. "env")
require(config_dir .. "keybindings")
require(config_dir .. "windowrules")
require(config_dir .. "input")
require(config_dir .. "animations")
require(config_dir .. "autostart")

hl.config({
    general = {
        gaps_in = 2,
        gaps_out = 4,
        border_size = 2,
        col = {
            active_border = {
                colors = { "rgba(b4befeff)", "rgba(cba6f7ff)" },
                angle = 45,
            },
            inactive_border = "rgba(45475aaa)",
        },
        resize_on_border = false,
        allow_tearing = false,
        layout = "dwindle",
    },
    dwindle = {
        preserve_split = true,
    },
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo = true,
        focus_on_activate = true,
    },
    decoration = {
        rounding = 10,
        active_opacity = 1.0,
        inactive_opacity = 1.0,
        blur = {
            enabled = true,
            size = 6,
            passes = 2,
            vibrancy = 0.1696,
        },
    },
})

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace",
})
