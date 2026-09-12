local home = os.getenv("HOME")

require(home .. "/.local/share/blankweave/hypr/hyprland")
require(home .. "/.config/hypr/env")
require(home .. "/.config/hypr/monitors")

-- Monitor arrangement chosen in the bar's display panel. The file is written
-- only by monitor-layout.sh and is absent until a position has been picked;
-- a broken or missing file must never keep the compositor from starting.
pcall(dofile, home .. "/.config/blankweave/monitors.lua")
