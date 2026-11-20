-- Hyprland speed is in deciseconds: 2 = 200 ms, 2.5 = 250 ms.
hl.config({ animations = { enabled = true },
    ecosystem = { no_update_news = true, no_donation_nag = true },
})

hl.curve("easeOut", {
    type = "bezier",
    points = { { 0.0, 0.0 }, { 0.2, 1.0 } },
})

hl.animation({ leaf = "windows", enabled = true, speed = 2.5, bezier = "easeOut", style = "popin 96%" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 2.5, bezier = "easeOut", style = "popin 96%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2, bezier = "easeOut", style = "popin 96%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 2.5, bezier = "easeOut" })
hl.animation({ leaf = "fade", enabled = true, speed = 2, bezier = "easeOut" })
hl.animation({ leaf = "border", enabled = true, speed = 2, bezier = "easeOut" })
hl.animation({ leaf = "borderangle", enabled = false, speed = 2, bezier = "easeOut" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 2.5, bezier = "easeOut", style = "slide" })

-- These surfaces own their transitions in QML, including popups on the bar.
-- Exact namespace matches keep unrelated layer clients unaffected.
hl.layer_rule({ match = { namespace = "^blankweave-bar$" }, no_anim = true })
hl.layer_rule({ match = { namespace = "^blankweave-launcher$" }, no_anim = true })
hl.layer_rule({ match = { namespace = "^blankweave-low-battery$" }, no_anim = true })
hl.layer_rule({ match = { namespace = "^blankweave-osd$" }, no_anim = true })
hl.layer_rule({ match = { namespace = "^blankweave-welcome$" }, no_anim = true })
hl.layer_rule({ match = { namespace = "^blankweave-voxtype-transcript$" }, no_anim = true })

-- Apply accessibility preferences after animation defaults, before personal overrides.
_G.blankweave_accessibility_revision = "defaults"
local path = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config"))
    .. "/blankweave/accessibility.lua"
local file, message, code = io.open(path, "r")
if file then
    file:close()
    dofile(path)
elseif code ~= 2 then
    error(message)
end
