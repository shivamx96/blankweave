.pragma library

// Stable IDs are the contract between a page and its backend. A missing backend
// leaves a control in preview; catalog entries never execute commands or write.
var pages = [
    { id: "appearance", title: "Appearance", icon: "󰏘", description: "Make this desktop yours.", groups: [
        { title: "Theme & color", rows: [
            { id: "theme", title: "Desktop theme", description: "Colors, wallpaper, and application styling.", kind: "choice", options: [], live: true },
            { id: "mode", title: "Color mode", description: "Use the dark or light version of your theme.", kind: "choice", options: ["Dark", "Light"], live: true }
        ] },
        { title: "Desktop bar", rows: [
            { id: "bar-position", title: "Position", description: "Choose the screen edge on every display.", kind: "choice", options: ["Top", "Bottom"], live: true },
            { id: "bar-visibility", title: "Visibility", description: "Keep the bar visible, hide in fullscreen, or reveal at the edge.", kind: "choice", options: ["Always visible", "Hide in fullscreen", "Auto-hide"], live: true },
            { id: "widgets", title: "Widgets & order", description: "Choose what appears in your bar.", kind: "action", action: "Customize" }
        ] },
        { title: "Personalization", rows: [
            { id: "wallpaper", title: "Wallpaper", description: "Choose a background and fit for each display.", kind: "action", action: "Choose image" },
            { id: "fonts", title: "Interface font", description: "Adjust text size and typeface.", kind: "choice", options: ["Default", "Large"] },
            { id: "cursor", title: "Pointer size", description: "Make the pointer easier to see.", kind: "choice", options: ["Default", "Large", "Extra large"] }
        ] }
    ] },
    { id: "displays", title: "Displays", icon: "󰍹", description: "Arrange your workspace, wherever you connect.", groups: [
        { title: "Connected displays", rows: [
            { id: "scale", title: "Scaling", description: "Change the size of text and applications on the selected display.", kind: "choice", options: [], live: true },
            { id: "brightness", title: "Brightness", description: "Adjust the selected display’s brightness.", kind: "slider", minimum: 5, maximum: 100, live: true },
            { id: "arrangement", title: "Saved display position", description: "Place an external display left, right, above, or below the existing desktop layout.", kind: "choice", options: [], live: true },
            { id: "mirroring", title: "Mirror displays", description: "Show the same content on multiple displays.", kind: "choice", live: true },
            { id: "resolution", title: "Resolution & refresh rate", description: "Choose a supported mode for each display.", kind: "choice", live: true }
        ] },
        { title: "Comfort & presets", rows: [
            { id: "night-light", title: "Night light", description: "Use warmer colors on all displays, even when Settings is closed.", kind: "night-light", live: true },
            { id: "display-presets", title: "Saved monitor setups", description: "Save modes, scaling, positions, and mirroring. Restore with the same displays connected.", kind: "presets", live: true },
            { id: "color-profile", title: "Color profiles", description: "Assign an RGB display ICC profile to the selected display. Profiles use SDR color output.", kind: "color-profile", live: true }
        ] }
    ] },
    { id: "sound", title: "Sound", icon: "󰕾", description: "Your speakers, microphone, dictation, and event sounds.", groups: [
        { title: "Playback & recording", rows: [
            { id: "output", title: "Output device & volume", description: "Choose the default playback device and adjust its volume.", kind: "sound-output", live: true },
            { id: "input", title: "Microphone & input level", description: "Choose a microphone, adjust gain or mute it, and check its signal.", kind: "sound-input", live: true }
        ] },
        { title: "Voice & feedback", rows: [
            { id: "dictation", title: "Local voice dictation", description: "Check dictation status, record speech, and recover your latest transcript.", kind: "dictation", live: true },
            { id: "sound-alerts", title: "System sounds", description: "Choose a sound theme and enable event or input feedback in supported apps.", kind: "system-sounds", live: true }
        ] }
    ] },
    { id: "network", title: "Network & Bluetooth", icon: "󰖩", description: "Connect to networks and nearby devices.", groups: [
        { title: "Connections", rows: [
            { id: "wifi", title: "Wi-Fi", description: "Discover networks and manage saved connections.", kind: "action", action: "Manage" },
            { id: "ethernet", title: "Ethernet, DNS & proxy", description: "Configure wired connections and network settings.", kind: "action", action: "Configure" },
            { id: "bluetooth", title: "Bluetooth devices", description: "Pair, connect, and forget accessories.", kind: "action", action: "Manage devices" },
            { id: "airplane", title: "Airplane mode", description: "Turn off wireless radios.", kind: "toggle" }
        ] },
        { title: "Sharing & remote access", rows: [
            { id: "vpn", title: "VPN & Tailscale", description: "Manage private networks and imported VPN profiles.", kind: "action", action: "Configure" },
            { id: "hotspot", title: "Wi-Fi hotspot", description: "Share your connection with other devices.", kind: "toggle" },
            { id: "sharing", title: "File sharing", description: "Configure nearby sharing and network folders.", kind: "action", action: "Configure" }
        ] }
    ] },
    { id: "power", title: "Power", icon: "󰁹", description: "Balance performance, comfort, and battery life.", groups: [
        { title: "Energy", rows: [
            { id: "profile", title: "Power profile", description: "Choose a balance of performance and energy use.", kind: "choice", options: ["Balanced", "Power saver", "Performance"] },
            { id: "automatic-power", title: "Automatic power profiles", description: "Choose profiles for charging, battery, and low battery.", kind: "toggle" },
            { id: "battery-health", title: "Battery health & charge limit", description: "Review wear and configure supported charge limits.", kind: "action", action: "View details" }
        ] },
        { title: "Idle & sleep", rows: [
            { id: "screen-off", title: "Turn off screen after", description: "Set separate timeouts for battery and plugged-in use.", kind: "choice", options: ["5 minutes", "10 minutes", "15 minutes", "Never"] },
            { id: "sleep", title: "Suspend & lid behavior", description: "Choose when the computer sleeps.", kind: "action", action: "Configure" },
            { id: "awake", title: "Keep awake", description: "Temporarily prevent idle sleep with an expiry time.", kind: "choice", options: ["Off", "30 minutes", "1 hour", "2 hours"] },
            { id: "hibernate", title: "Hibernation", description: "Configure saving your session to disk where supported.", kind: "action", action: "Set up" }
        ] }
    ] },
    { id: "input", title: "Input & Accessibility", icon: "󰌌", description: "Make your computer work the way you do.", groups: [
        { title: "Keyboard & pointer", rows: [
            { id: "layouts", title: "Keyboard layouts & languages", description: "Add layouts, input methods, and a layout switcher.", kind: "action", action: "Manage" },
            { id: "shortcuts", title: "Keyboard shortcuts", description: "Discover and customize desktop shortcuts.", kind: "action", action: "Edit shortcuts" },
            { id: "pointer", title: "Mouse & touchpad", description: "Set sensitivity, scrolling, gestures, and tap to click.", kind: "action", action: "Configure" }
        ] },
        { title: "Accessibility", rows: [
            { id: "large-text", title: "Large text", description: "Increase text size throughout the interface.", kind: "toggle" },
            { id: "contrast", title: "High contrast", description: "Make controls and text easier to distinguish.", kind: "toggle" },
            { id: "motion", title: "Reduce motion", description: "Limit interface animations.", kind: "toggle" },
            { id: "assistive", title: "Screen reader, magnifier & on-screen keyboard", description: "Set up assistive tools and their shortcuts.", kind: "action", action: "Configure" }
        ] }
    ] },
    { id: "apps", title: "Apps", icon: "󰀻", description: "Manage your applications and their access.", groups: [
        { title: "Applications", rows: [
            { id: "installed", title: "Installed applications", description: "Browse, install, and remove software.", kind: "action", action: "Browse apps" },
            { id: "defaults", title: "Default applications", description: "Choose a browser, email handler, and file associations.", kind: "action", action: "Choose defaults" },
            { id: "startup", title: "Startup applications", description: "Choose what starts when you sign in.", kind: "action", action: "Manage" },
            { id: "permissions", title: "Application permissions", description: "Review supported camera, microphone, and file permissions.", kind: "action", action: "Review" },
            { id: "webapps", title: "Web apps", description: "Add and manage sites that open as applications.", kind: "action", action: "Manage" }
        ] },
        { title: "Notifications", rows: [
            { id: "dnd", title: "Do not disturb", description: "Pause notifications or create a quiet-hours schedule.", kind: "toggle" },
            { id: "notifications", title: "Notification preferences", description: "Choose which apps can notify you.", kind: "action", action: "Configure" }
        ] }
    ] },
    { id: "storage", title: "Storage & Backup", icon: "󰋊", description: "Look after your files and the places they live.", groups: [
        { title: "Storage", rows: [
            { id: "disk-usage", title: "Disk usage & cleanup", description: "Review space used by files, applications, and caches.", kind: "action", action: "Review storage" },
            { id: "drives", title: "Drives & removable media", description: "Mount, unlock, and safely eject external storage.", kind: "action", action: "Manage drives" },
            { id: "disk-health", title: "Disk health", description: "Review supported drive health information.", kind: "action", action: "View details" }
        ] },
        { title: "Backup & recovery", rows: [
            { id: "backup", title: "Scheduled file backups", description: "Choose files, destinations, encryption, and retention.", kind: "action", action: "Set up backups" },
            { id: "restore", title: "Restore files", description: "Browse a backup and recover individual files.", kind: "action", action: "Browse backups" },
            { id: "snapshots", title: "System snapshots", description: "Configure snapshots and review recovery options.", kind: "action", action: "Configure" }
        ] }
    ] },
    { id: "system", title: "System", icon: "󰒓", description: "Keep your desktop current and running well.", groups: [
        { title: "Maintenance", rows: [
            { id: "updates", title: "Updates & release notes", description: "Review Blankweave and package updates.", kind: "action", action: "Check updates" },
            { id: "firmware", title: "Device firmware", description: "Check for supported BIOS and peripheral updates.", kind: "action", action: "Check firmware" },
            { id: "diagnostics", title: "Diagnostics & recovery", description: "Run health checks and review configuration rollback.", kind: "action", action: "Open diagnostics" }
        ] },
        { title: "This computer", rows: [
            { id: "accounts", title: "Users & sign-in", description: "Manage accounts, passwords, and sign-in preferences.", kind: "action", action: "Manage" },
            { id: "datetime", title: "Date, time & region", description: "Choose a timezone, formats, and clock synchronization.", kind: "action", action: "Configure" },
            { id: "printers", title: "Printers & scanners", description: "Add devices and manage print jobs.", kind: "action", action: "Manage devices" },
            { id: "about", title: "About this computer", description: "View hardware, software versions, and support information.", kind: "action", action: "View details" }
        ] }
    ] }
];

function matches(page, query) {
    var terms = String(query || "").toLowerCase().trim().split(/\s+/);
    var content = [page.title, page.description];
    page.groups.forEach(function(group) {
        content.push(group.title);
        group.rows.forEach(function(row) { content.push(row.title, row.description); });
    });
    var text = content.join(" ").toLowerCase();
    return terms.every(function(term) { return text.indexOf(term) !== -1; });
}

function search(query) {
    return pages.filter(function(page) { return matches(page, query); });
}
