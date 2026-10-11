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

-- Keep games rendering while another workspace is on screen. A game presents
-- through the compositor, so a window Hyprland is not drawing never gets its
-- buffers back, Present blocks, and the game's main thread stalls with it:
-- Cities: Skylines II loaded one prefab a minute from an off-screen
-- workspace. misc.render_unfocused_fps (default 15) bounds the cost.
hl.window_rule({
    name = "render-unfocused-steam-games",
    match = { class = "^steam_app_[0-9]+$" },
    render_unfocused = true,
})
