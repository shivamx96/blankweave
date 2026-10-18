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
            { id: "widgets", title: "Widgets & order", description: "Choose what appears in your bar.", kind: "widgets", live: true }
        ] },
        { title: "Personalization", rows: [
            { id: "wallpaper", title: "Wallpaper", description: "Choose a background and fit for each display.", kind: "wallpaper", live: true },
            { id: "fonts", title: "Text size", description: "Resize shell text and text in compatible applications.", kind: "interface-size", live: true },
            { id: "cursor", title: "Pointer size", description: "Make the pointer easier to see.", kind: "interface-size", live: true }
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
            { id: "wifi", title: "Wi-Fi", description: "Connect to nearby networks and manage saved connections.", kind: "wifi", live: true },
            { id: "ethernet", title: "Ethernet & DNS", description: "Manage wired connections, view addresses, and choose DNS for Ethernet or Wi-Fi.", kind: "network", live: true },
            { id: "bluetooth", title: "Bluetooth devices", description: "Discover, pair, connect, and forget accessories.", kind: "bluetooth", live: true },
            { id: "airplane", title: "Airplane mode", description: "Turn off wireless radios and restore their previous state.", kind: "airplane", live: true }
        ] },
        { title: "Sharing & remote access", rows: [
            { id: "vpn", title: "VPN & Tailscale", description: "Manage private networks and imported VPN profiles.", kind: "operations", live: true },
            { id: "hotspot", title: "Wi-Fi hotspot", description: "Share a connection through a temporary, password-protected Wi-Fi network.", kind: "hotspot", live: true },
            { id: "sharing", title: "File sharing", description: "Configure nearby sharing and network folders.", kind: "operations", live: true }
        ] }
    ] },
    { id: "power", title: "Power", icon: "󰁹", description: "Balance performance, comfort, and battery life.", groups: [
        { title: "Energy", rows: [
            { id: "profile", title: "Power profile", description: "Choose a balance of performance and energy use.", kind: "power-profile", live: true },
            { id: "automatic-power", title: "Automatic power profiles", description: "Choose profiles for plugged-in use, battery, and low battery.", kind: "automatic-power", live: true },
            { id: "battery-health", title: "Battery health & charge limit", description: "Review battery health and enable supported charge limits.", kind: "battery-health", live: true }
        ] },
        { title: "Idle & sleep", rows: [
            { id: "screen-off", title: "Idle timeouts", description: "Choose dimming, locking, screen-off, and sleep delays for battery and plugged-in use.", kind: "idle", live: true },
            { id: "hibernate", title: "Hibernation", description: "Configure saving your session to disk where supported.", kind: "operations", live: true }
        ] }
    ] },
    { id: "input", title: "Input & Accessibility", icon: "󰌌", description: "Make your computer work the way you do.", groups: [
        { title: "Keyboard & pointer", rows: [
            { id: "layouts", title: "Keyboard layouts & languages", description: "Add keyboard layouts and variants, choose a switching shortcut, and switch layouts.", kind: "keyboard", live: true },
            { id: "shortcuts", title: "Keyboard shortcuts", description: "Discover desktop shortcuts, change key combinations, and check conflicts.", kind: "shortcuts", live: true },
            { id: "pointer", title: "Mouse & touchpad", description: "Adjust speed, acceleration, scrolling, buttons, tap to click, and typing protection.", kind: "pointer", live: true }
        ] },
        { title: "Accessibility", rows: [
            { id: "large-text", title: "Text size", description: "The same text-size preference as Appearance.", kind: "interface-size", live: true },
            { id: "contrast", title: "High contrast", description: "Increase shell contrast and request it in compatible applications.", kind: "accessibility", live: true },
            { id: "motion", title: "Reduce motion", description: "Disable desktop transitions and request fewer animations in compatible applications.", kind: "accessibility", live: true },
            { id: "assistive", title: "Screen reader, magnifier & on-screen keyboard", description: "Set up assistive tools and their shortcuts.", kind: "operations", live: true }
        ] }
    ] },
    { id: "apps", title: "Apps", icon: "󰀻", description: "Manage your applications and their access.", groups: [
        { title: "Applications", rows: [
            { id: "installed", title: "Installed applications", description: "Browse, install, and remove software.", kind: "operations", live: true },
            { id: "defaults", title: "Default applications", description: "Choose handlers for web links, email, folders, documents, and media.", kind: "default-apps", live: true },
            { id: "startup", title: "Startup applications", description: "Choose what starts when you sign in.", kind: "startup", live: true },
            { id: "permissions", title: "Application permissions", description: "Review supported camera, microphone, and file permissions.", kind: "operations", live: true },
            { id: "webapps", title: "Web apps", description: "Add and manage sites that open as applications.", kind: "webapps", live: true }
        ] },
        { title: "Notifications", rows: [
            { id: "dnd", title: "Do not disturb", description: "Pause notifications or create a quiet-hours schedule.", kind: "notifications", live: true },
            { id: "notifications", title: "Notification preferences", description: "Choose which apps can show popups.", kind: "notifications", live: true }
        ] }
    ] },
    { id: "storage", title: "Storage & Backup", icon: "󰋊", description: "Look after your files and the places they live.", groups: [
        { title: "Storage", rows: [
            { id: "disk-usage", title: "Disk usage & cleanup", description: "Review space used by files, applications, and caches.", kind: "operations", live: true },
            { id: "drives", title: "Drives & removable media", description: "Mount, unlock, and safely eject external storage.", kind: "operations", live: true },
            { id: "disk-health", title: "Disk health", description: "Review supported drive health information.", kind: "operations", live: true }
        ] },
        { title: "Backup & recovery", rows: [
            { id: "backup", title: "Scheduled file backups", description: "Choose files, destinations, encryption, and retention.", kind: "operations", live: true },
            { id: "restore", title: "Restore files", description: "Browse a backup and recover individual files.", kind: "operations", live: true },
            { id: "snapshots", title: "System snapshots", description: "Configure snapshots and review recovery options.", kind: "operations", live: true }
        ] }
    ] },
    { id: "system", title: "System", icon: "󰒓", description: "Keep your desktop current and running well.", groups: [
        { title: "Maintenance", rows: [
            { id: "updates", title: "Updates & release notes", description: "Review Blankweave and package updates.", kind: "operations", live: true },
            { id: "firmware", title: "Device firmware", description: "Check for supported BIOS and peripheral updates.", kind: "operations", live: true },
            { id: "diagnostics", title: "Diagnostics", description: "Run read-only health checks and copy a local report.", kind: "system-info", live: true }
        ] },
        { title: "This computer", rows: [
            { id: "accounts", title: "Users & sign-in", description: "Manage accounts, passwords, and sign-in preferences.", kind: "operations", live: true },
            { id: "datetime", title: "Date, time & region", description: "Choose a timezone, formats, and clock synchronization.", kind: "operations", live: true },
            { id: "printers", title: "Printers & scanners", description: "Add devices and manage print jobs.", kind: "operations", live: true },
            { id: "about", title: "About this computer", description: "View hardware, software versions, and support information.", kind: "system-info", live: true }
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

// Search each setting independently; never combine words from unrelated rows.
var searchAliases = {
    "vpn": "vpn tailscale private network tunnel",
    "datetime": "timezone time zone clock date locale region language ntp",
    "assistive": "screen reader orca magnifier zoom on screen keyboard accessibility",
    "backup": "backup backups back up schedule retention restore point restic",
    "restore": "restore recover recovery backup files",
    "snapshots": "snapshots snapper system recovery",
    "disk-usage": "disk space storage usage cleanup free space",
    "installed": "install uninstall remove software packages applications",
    "firmware": "firmware bios uefi device update",
    "printers": "printer scanner print scan",
    "hibernate": "hibernate hibernation resume swap"
};

function searchSettings(query) {
    var normalized = String(query || "").toLowerCase().trim();
    if (!normalized) return [];
    var terms = normalized.split(/\s+/);
    var matches = [];
    pages.forEach(function(page) {
        page.groups.forEach(function(group) {
            group.rows.forEach(function(row) {
                var title = row.title.toLowerCase();
                var own = [row.title, row.description, searchAliases[row.id] || ""].join(" ").toLowerCase();
                var text = [own, page.title, group.title].join(" ").toLowerCase();
                if (!terms.every(function(term) { return text.indexOf(term) !== -1; })) return;
                var score = title === normalized ? 0 : title.indexOf(normalized) !== -1 ? 1
                    : terms.every(function(term) { return own.indexOf(term) !== -1; }) ? 2 : 3;
                matches.push({id: row.id, pageId: page.id, title: row.title,
                    description: row.description, breadcrumb: page.title + " › " + group.title, score: score});
            });
        });
    });
    return matches.sort(function(a, b) { return a.score - b.score; });
}
