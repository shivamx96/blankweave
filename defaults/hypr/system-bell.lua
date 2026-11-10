-- Preserve the compositor default until the user chooses a bell preference.
hl.config({ misc = { bell_sound = "default" } })
_G.blankweave_bell_revision = "defaults"
local path = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config"))
    .. "/blankweave/system-bell.lua"
local file, message, code = io.open(path, "r")
if file then
    file:close()
    dofile(path)
elseif code ~= 2 then
    error(message)
end
