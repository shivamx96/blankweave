-- Missing overrides are optional; errors in an existing file must reach
-- Hyprland's validator and error UI instead of silently dropping user settings.
local path = os.getenv("HOME") .. "/.config/blankweave/overrides/hyprland.lua"
local file, message, code = io.open(path, "r")
if file then
    file:close()
    dofile(path)
elseif code ~= 2 then
    error(message)
end
