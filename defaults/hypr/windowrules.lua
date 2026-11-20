-- Utility windows must not rearrange the tiled workspace. Limit sizes to
-- available logical monitor space, including small/fractionally scaled outputs.
local function utility(name, match, width, height)
    hl.window_rule({
        name = name, match = match, float = true, center = true,
        size = { "min(" .. width .. ", monitor_w*0.9)", "min(" .. height .. ", monitor_h*0.85)" },
    })
end
utility("float-pavucontrol", { class = "^(org\\.pulseaudio\\.pavucontrol|pavucontrol)$" }, 800, 600)
utility("float-blueman", { class = "^blueman-(manager|assistant|sendto)$" }, 800, 600)
utility("float-portal-gtk", { class = "^xdg-desktop-portal-gtk$" }, 960, 640)
utility("float-portal-hyprland", { class = "^xdg-desktop-portal-hyprland$" }, 960, 640)
utility("float-polkit", { class = "^([Pp]olkit-gnome-authentication-agent-1|org\\.gnome\\.PolicyKit1)$" }, 520, 320)
-- Quickshell's default app ID is org.quickshell. Other shell windows are excluded.
utility("float-blankweave-settings", { class = "^org\\.quickshell$", title = "^Blankweave Settings$" }, 1040, 760)

hl.window_rule({
    name = "picture-in-picture",
    match = {
        class = "^(zen|zen-browser|firefox|helium|helium-browser|chromium|google-chrome|brave-browser)$",
        title = "^(Picture-in-Picture|Picture in picture)$",
    },
    float = true, pin = true, no_initial_focus = true,
    -- Floating/pinned windows stay above the tiled layer; keep the video ratio.
    keep_aspect_ratio = true,
    size = { "monitor_w*0.25", "monitor_h*0.25" },
    move = { "monitor_w-window_w-24", "monitor_h-window_h-48" },
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
