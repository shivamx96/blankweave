hl.config({
    input = {
        kb_layout = "us",
        kb_variant = "",
        kb_model = "",
        kb_options = "",
        kb_rules = "",
        follow_mouse = 1,
        sensitivity = 0,
        touchpad = {
            natural_scroll = true,
            tap_to_click = true,
        },
    },
})

-- Saved pointer choices load before personal overrides. Missing preferences
-- are optional; a corrupt existing file must be visible in configerrors.
_G.blankweave_pointer_revision = "defaults"
local pointer_path = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config"))
    .. "/blankweave/pointer.lua"
local pointer_file, pointer_error, pointer_code = io.open(pointer_path, "r")
if pointer_file then
    pointer_file:close()
    dofile(pointer_path)
elseif pointer_code ~= 2 then
    error(pointer_error)
end
