-- TODO: Convert these to floating windows
-- Size hints
hl.window_rule({
    name = "size-pavucontrol",
    match = { class = "pavucontrol" },
    size = { 800, 600 },
})

hl.window_rule({
    name = "size-blueman-manager",
    match = { class = "blueman-manager" },
    size = { 800, 600 },
})
