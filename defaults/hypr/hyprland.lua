local config_dir = os.getenv("HOME") .. "/.local/share/hyprarch/hypr/"

require(config_dir .. "env")
require(config_dir .. "keybindings")
require(config_dir .. "windowrules")
require(config_dir .. "input")
require(config_dir .. "animations")
require(config_dir .. "autostart")

-- Window border colours come from the active theme: theme-apply.sh renders
-- ~/.config/hyprarch/theme.lua, which is absent until the first apply, so fall
-- back to the bundled default palette rather than refusing to start.
local theme_ok, theme = pcall(dofile, os.getenv("HOME") .. "/.config/hyprarch/theme.lua")
if not theme_ok or type(theme) ~= "table" then
    theme = {
        active_border = { "rgba(3b82f6ff)", "rgba(67a6ffff)" },
        inactive_border = "rgba(33476aff)",
        cursor_theme = "Bibata-Modern-Ice",
    }
end

-- The cursor theme is a theme token too. These variables only seed the session;
-- theme-apply.sh switches a running compositor with `hyprctl setcursor`.
hl.env("HYPRCURSOR_THEME", theme.cursor_theme)
hl.env("XCURSOR_THEME", theme.cursor_theme)

hl.config({
    general = {
        gaps_in = 2,
        gaps_out = 4,
        border_size = 2,
        col = {
            active_border = {
                colors = theme.active_border,
                angle = 45,
            },
            inactive_border = theme.inactive_border,
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
