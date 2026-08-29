hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- Chromium's os_crypt only talks to the Secret Service on desktops it recognises.
-- It does not know Hyprland, so Electron apps (T3 Code, Slack, Bruno) would pick
-- the basic_text backend and safeStorage would refuse to persist credentials.
-- This legacy GNOME variable is Chromium's final fallback; Qt and GTK ignore it
-- while XDG_CURRENT_DESKTOP is set, and xdg-utils merely routes xdg-open through
-- gio open, which honours the same mimeapps.list.
hl.env("GNOME_DESKTOP_SESSION_ID", "hyprarch")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XCURSOR_SIZE", "24")
