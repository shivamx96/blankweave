.pragma library

// Stable IDs are the contract between a page and its backend. A missing backend
// leaves a control disabled; catalog entries never execute commands or write.
var pages = [
    { id: "appearance", title: "Appearance", icon: "󰏘", description: "Make this desktop yours.", groups: [
        { title: "Theme & color", rows: [
            { id: "theme", relatedFiles: ["~/.config/blankweave/theme.lua"], file: "~/.config/blankweave/theme.json", aliases: ["theme", "desktop", "appearance", "colors", "styles"], title: "Desktop theme", description: "Colors, wallpaper, and application styling.", kind: "choice", live: true },
            { id: "mode", file: "~/.config/blankweave/theme.json", aliases: ["dark", "mode", "light", "theme", "automatic"], title: "Dark mode", description: "Turn off to use the light version of your theme.", kind: "switch", live: true }
        ] },
        { title: "Time & weather", rows: [
            { id: "time-format", file: "~/.config/blankweave/shell.json", aliases: ["clock", "12 hour", "24 hour", "am pm", "time", "locale"], title: "Time format", description: "Choose how shell clocks show the time.", kind: "choice", live: true },
            { id: "temperature-unit", file: "~/.config/blankweave/shell.json", aliases: ["weather", "temperature", "celsius", "fahrenheit", "units", "locale"], title: "Temperature unit", description: "Choose weather temperature units.", kind: "choice", live: true }
        ] },
        { title: "Desktop bar", rows: [
            { id: "bar-position", file: "~/.config/blankweave/shell.json", aliases: ["bar", "panel", "position", "top", "bottom", "screen", "edge"], title: "Position", description: "Choose the screen edge on every display.", kind: "choice", live: true },
            { id: "bar-visibility", file: "~/.config/blankweave/shell.json", aliases: ["bar", "panel", "visibility", "always", "visible", "hide", "fullscreen", "auto"], title: "Visibility", description: "Keep the bar visible, hide in fullscreen, or reveal at the edge.", kind: "choice", live: true },
            { id: "widgets", file: "~/.config/blankweave/shell.json", aliases: ["widgets", "order", "bar", "panel", "clock", "tray", "battery", "weather"], title: "Widgets & order", description: "Choose what appears in your bar.", kind: "widgets", live: true }
        ] },
        { title: "Personalization", rows: [
            { id: "wallpaper", file: "~/.config/blankweave/wallpapers.json", aliases: ["wallpaper", "background", "image", "fit", "fill", "stretch", "center", "tile", "display"], title: "Wallpaper", description: "Choose a background and fit for each display.", kind: "wallpaper", live: true },
            { id: "fonts", relatedFiles: ["~/.config/blankweave/interface.lua"], file: "~/.config/blankweave/interface.json", aliases: ["font", "typeface", "text", "size", "interface", "zoom"], title: "Text size", description: "Resize shell text and text in compatible applications.", kind: "interface-size", live: true },
            { id: "cursor", relatedFiles: ["~/.config/blankweave/interface.lua"], file: "~/.config/blankweave/interface.json", aliases: ["cursor", "pointer", "mouse", "size"], title: "Pointer size", description: "Make the pointer easier to see.", kind: "interface-size", live: true }
        ] }
    ] },
    { id: "displays", title: "Displays", icon: "󰍹", description: "Arrange your workspace, wherever you connect.", groups: [
        { title: "Connected displays", rows: [
            { id: "scale", relatedFiles: ["~/.config/blankweave/monitors.lua"], file: "~/.config/blankweave/monitors.json", aliases: ["scale", "scaling", "hidpi", "display", "size"], title: "Scaling", description: "Change the size of text and applications on the selected display.", kind: "choice", live: true },
            { id: "brightness", requires: "display-brightness", aliases: ["brightness", "backlight", "screen", "dim"], title: "Brightness", description: "Adjust the selected display’s brightness.", kind: "slider", minimum: 5, maximum: 100, live: true },
            { id: "arrangement", relatedFiles: ["~/.config/blankweave/monitors.lua"], file: "~/.config/blankweave/monitors.json", aliases: ["arrange", "monitor", "display", "position", "left", "right", "above", "below", "automatic"], title: "Saved display position", description: "Place an external display left, right, above, or below the existing desktop layout.", kind: "choice", live: true },
            { id: "mirroring", relatedFiles: ["~/.config/blankweave/monitors.lua"], file: "~/.config/blankweave/monitors.json", aliases: ["mirror", "duplicate", "extend", "displays"], title: "Mirror displays", description: "Show the same content on multiple displays.", kind: "choice", live: true },
            { id: "resolution", relatedFiles: ["~/.config/blankweave/monitors.lua"], file: "~/.config/blankweave/monitors.json", aliases: ["resolution", "refresh", "rate", "hertz", "hz", "display", "mode", "hidpi"], title: "Resolution & refresh rate", description: "Choose a supported mode for each display.", kind: "choice", live: true }
        ] },
        { title: "Comfort & presets", rows: [
            { id: "night-light", file: "~/.config/blankweave/night-light.json", aliases: ["night", "shift", "nightlight", "light", "blue", "warmth", "temperature", "schedule", "sunset", "sunrise"], title: "Night light", description: "Use warmer colors on all displays, even when Settings is closed.", kind: "night-light", live: true },
            { id: "display-presets", file: "~/.config/blankweave/monitor-setups.json", aliases: ["monitor", "setup", "preset", "save", "restore", "delete", "modes", "positions"], title: "Saved monitor setups", description: "Save modes, scaling, positions, and mirroring. Restore with the same displays connected.", kind: "presets", live: true },
            { id: "color-profile", file: "~/.config/blankweave/monitors.json", aliases: ["color", "colour", "profile", "icc", "rgb", "sdr", "assign", "remove"], title: "Color profiles", description: "Assign an RGB display ICC profile to the selected display. Profiles use SDR color output.", kind: "color-profile", live: true }
        ] }
    ] },
    { id: "sound", title: "Sound", icon: "󰕾", description: "Your speakers, microphone, dictation, and event sounds.", groups: [
        { title: "Playback & recording", rows: [
            { id: "output", store: "PipeWire / WirePlumber state", aliases: ["volume", "speaker", "speakers", "headphones", "audio", "output", "device", "mute", "balance"], title: "Output device & volume", description: "Choose the default playback device and adjust its volume.", kind: "sound-output", live: true },
            { id: "input", aliases: ["microphone", "mic", "recording", "input", "gain", "mute", "signal"], title: "Microphone & input level", description: "Choose a microphone, adjust gain or mute it, and check its signal.", kind: "sound-input", live: true }
        ] },
        { title: "Voice & feedback", rows: [
            { id: "dictation", aliases: ["voice", "dictation", "speech", "transcript", "record", "stop", "cancel", "restart", "copy"], title: "Local voice dictation", description: "Check dictation status, record speech, and recover your latest transcript.", kind: "dictation", live: true },
            { id: "sound-alerts", file: "~/.config/blankweave/system-bell.json", store: "desktop settings database: org.gnome.desktop.sound", aliases: ["system", "bell", "beep", "alert", "event", "sounds", "preview", "volume"], title: "System sounds", description: "Choose app event sounds and control the desktop system bell.", kind: "system-sounds", live: true }
        ] }
    ] },
    { id: "network", title: "Network & Bluetooth", icon: "󰖩", description: "Connect to networks and nearby devices.", groups: [
        { title: "Connections", rows: [
            { id: "wifi", store: "NetworkManager connection profile", requires: "wifi", aliases: ["wifi", "wireless", "internet", "network", "connect", "disconnect", "password", "saved", "forget", "scan"], title: "Wi-Fi", description: "Connect to nearby networks and manage saved connections.", kind: "wifi", live: true },
            { id: "ethernet", store: "NetworkManager connection profile", aliases: ["ethernet", "wired", "dns", "address", "ip", "automatic", "manual", "gateway"], title: "Ethernet & DNS", description: "Manage wired connections, view addresses, and choose DNS for Ethernet or Wi-Fi.", kind: "network", live: true },
            { id: "bluetooth", store: "BlueZ device state", requires: "bluetooth", aliases: ["bluetooth", "pair", "discover", "connect", "disconnect", "forget", "accessories"], title: "Bluetooth devices", description: "Discover, pair, connect, and forget accessories.", kind: "bluetooth", live: true },
            { id: "airplane", store: "rfkill / BlueZ; XDG state: blankweave/airplane.json", aliases: ["airplane", "flight", "mode", "wireless", "radios"], title: "Airplane mode", description: "Turn off wireless radios and restore their previous state.", kind: "airplane", live: true }
        ] },
        { title: "Sharing & remote access", rows: [
            { id: "vpn", store: "NetworkManager connection profiles / Tailscale state", aliases: ["vpn", "tailscale", "private", "network", "tunnel", "import", "connect", "disconnect"], title: "VPN & Tailscale", description: "Manage private networks and imported VPN profiles.", kind: "operations", live: true },
            { id: "hotspot", store: "NetworkManager connection profile", requires: "wifi", aliases: ["hotspot", "tethering", "wifi", "share", "connection", "ssid", "password", "stop", "start"], title: "Wi-Fi hotspot", description: "Share a connection through a temporary, password-protected Wi-Fi network.", kind: "hotspot", live: true },
            { id: "sharing", store: "Samba usershare database", aliases: ["file", "sharing", "nearby", "network", "folders", "samba"], title: "File sharing", description: "Configure nearby sharing and network folders.", kind: "operations", live: true }
        ] }
    ] },
    { id: "power", title: "Power", icon: "󰁹", description: "Balance performance, comfort, and battery life.", groups: [
        { title: "Energy", rows: [
            { id: "profile", store: "power-profiles-daemon state", aliases: ["power", "profile", "balanced", "performance", "saver", "energy"], title: "Power profile", description: "Choose a balance of performance and energy use.", kind: "power-profile", live: true },
            { id: "automatic-power", file: "~/.config/blankweave/power-profiles.json", requires: "battery", aliases: ["automatic", "power", "profile", "plugged", "in", "battery", "low", "threshold"], title: "Automatic power profiles", description: "Choose profiles for plugged-in use, battery, and low battery.", kind: "automatic-power", live: true },
            { id: "battery-health", store: "UPower charge thresholds", requires: "battery", aliases: ["battery", "charge", "limit", "health", "capacity", "charging", "threshold"], title: "Battery health & charge limit", description: "Review battery health and enable supported charge limits.", kind: "battery-health", live: true }
        ] },
        { title: "Idle & sleep", rows: [
            { id: "screen-off", file: "~/.config/blankweave/idle.json", aliases: ["suspend", "sleep", "idle", "lock", "screen", "off", "dim", "timeout", "delay", "plugged", "in"], title: "Idle timeouts", description: "Choose dimming, locking, screen-off, and sleep delays for plugged-in use.", kind: "idle", supply: "ac", live: true },
            { id: "idle-on-battery", file: "~/.config/blankweave/idle.json", requires: "battery", aliases: ["idle", "battery", "dim", "lock", "screen", "sleep"], title: "Idle timeouts on battery", description: "Choose dimming, locking, screen-off, and sleep delays on battery.", kind: "idle", supply: "battery", live: true },
            { id: "hibernate", file: "~/.config/blankweave/idle-hibernate", store: "logind / boot resume configuration", aliases: ["hibernate", "hibernation", "resume", "swap", "session", "disk"], title: "Hibernation", description: "Configure saving your session to disk where supported.", kind: "operations", live: true }
        ] }
    ] },
    { id: "input", store: "PipeWire / WirePlumber state", aliases: ["microphone", "mic", "recording", "input", "gain", "mute", "signal"], title: "Input & Accessibility", icon: "󰌌", description: "Make your computer work the way you do.", groups: [
        { title: "Keyboard & pointer", rows: [
            { id: "layouts", relatedFiles: ["~/.config/blankweave/keyboard.lua"], file: "~/.config/blankweave/keyboard.json", aliases: ["keyboard", "layouts", "languages", "repeat", "delay", "rate", "caps", "escape", "compose", "variants", "switching", "shortcut", "add", "remove"], title: "Keyboard layouts & languages", description: "Add keyboard layouts and variants, choose a switching shortcut, and switch layouts.", kind: "keyboard", live: true },
            { id: "shortcuts", relatedFiles: ["~/.config/blankweave/shortcuts.lua"], file: "~/.config/blankweave/shortcuts.json", aliases: ["shortcuts", "keybindings", "hotkeys", "key", "combinations", "conflicts", "reset"], title: "Keyboard shortcuts", description: "Discover desktop shortcuts, change key combinations, and check conflicts.", kind: "shortcuts", live: true },
            { id: "pointer", relatedFiles: ["~/.config/blankweave/pointer.lua"], file: "~/.config/blankweave/pointer.json", aliases: ["trackpad", "touchpad", "mouse", "pointer", "speed", "acceleration", "scrolling", "natural", "buttons", "tap", "click", "secondary", "clickfinger", "two-finger", "typing", "protection"], title: "Mouse & touchpad", description: "Adjust speed, acceleration, scrolling, buttons, tap to click, and typing protection.", kind: "pointer", live: true }
        ] },
        { title: "Accessibility", rows: [
            { id: "large-text", file: "~/.config/blankweave/interface.json", aliases: ["font", "typeface", "text", "size", "accessibility"], title: "Text size", description: "Open Text size in Appearance.", target: "fonts", kind: "link", live: true },
            { id: "contrast", relatedFiles: ["~/.config/blankweave/accessibility.lua"], file: "~/.config/blankweave/accessibility.json", aliases: ["high", "contrast", "accessibility", "theme"], title: "High contrast", description: "Increase shell contrast and request it in compatible applications.", kind: "accessibility", live: true },
            { id: "motion", relatedFiles: ["~/.config/blankweave/accessibility.lua"], file: "~/.config/blankweave/accessibility.json", aliases: ["reduce", "motion", "animations", "transitions", "accessibility"], title: "Reduce motion", description: "Disable desktop transitions and request fewer animations in compatible applications.", kind: "accessibility", live: true },
            { id: "assistive", file: "~/.config/blankweave/magnifier.lua", store: "desktop settings database: org.gnome.desktop.interface; XDG user systemd units", aliases: ["screen", "reader", "orca", "magnifier", "zoom", "on", "keyboard", "accessibility", "enable", "setup", "shortcuts"], title: "Screen reader, magnifier & on-screen keyboard", description: "Set up assistive tools and their shortcuts.", kind: "operations", live: true }
        ] }
    ] },
    { id: "apps", title: "Apps", icon: "󰀻", description: "Manage your applications and their access.", groups: [
        { title: "Applications", rows: [
            { id: "installed", store: "pacman package database", aliases: ["install", "uninstall", "remove", "software", "packages", "applications", "search"], title: "Installed applications", description: "Browse, install, and remove software.", kind: "operations", live: true },
            { id: "defaults", file: "~/.config/mimeapps.list", aliases: ["browser", "default", "apps", "applications", "web", "email", "folders", "documents", "media", "handlers"], title: "Default applications", description: "Choose handlers for web links, email, folders, documents, and media.", kind: "default-apps", live: true },
            { id: "startup", store: "XDG autostart desktop entries", aliases: ["autostart", "startup", "login", "items", "applications", "add", "remove", "enabled", "command"], title: "Startup applications", description: "Choose what starts when you sign in.", kind: "startup", live: true },
            { id: "permissions", store: "Flatpak permission database", aliases: ["application", "permissions", "camera", "microphone", "files", "access", "sandbox"], title: "Application permissions", description: "Review supported camera, microphone, and file permissions.", kind: "operations", live: true },
            { id: "webapps", store: "XDG applications desktop entries", aliases: ["web", "apps", "sites", "application", "name", "url", "add", "remove", "browser"], title: "Web apps", description: "Add and manage sites that open as applications.", kind: "webapps", live: true }
        ] }
    ] },
    { id: "alerts", title: "Notifications", description: "Popups and quiet hours.", groups: [
        { title: "Notifications", rows: [
            { id: "dnd", file: "~/.config/blankweave/notifications.json", aliases: ["dnd", "do", "not", "disturb", "focus", "quiet", "hours", "schedule", "start", "end", "notifications"], title: "Do not disturb", description: "Pause notifications or create a quiet-hours schedule.", kind: "notifications", live: true },
            { id: "notifications", file: "~/.config/blankweave/notifications.json", aliases: ["notification", "preferences", "popups", "apps", "history", "timeout"], title: "Notification preferences", description: "Choose which apps can show popups.", kind: "notifications", live: true }
        ] }
    ] },
    { id: "storage", title: "Storage & Backup", icon: "󰋊", description: "Look after your files and the places they live.", groups: [
        { title: "Storage", rows: [
            { id: "disk-usage", aliases: ["disk", "space", "storage", "usage", "cleanup", "free", "cache", "files", "disk space", "clean up", "paccache"], title: "Disk usage & cleanup", description: "Review cache sizes and clean Paru builds or old package versions. Never empty the pacman cache: rollback and offline repair depend on it.", kind: "operations", live: true },
            { id: "drives", aliases: ["drive", "removable", "media", "mount", "unlock", "eject", "storage"], title: "Drives & removable media", description: "Mount, unlock, and safely eject external storage.", kind: "operations", live: true },
            { id: "disk-health", aliases: ["disk", "drive", "health", "smart", "test"], title: "Disk health", description: "Review supported drive health information.", kind: "operations", live: true }
        ] },
        { title: "Backup & recovery", rows: [
            { id: "backup", file: "~/.config/blankweave/backup.json", aliases: ["backup", "backups", "back", "up", "schedule", "retention", "restore", "point", "restic", "destination", "encryption", "files", "password"], title: "Scheduled file backups", description: "Choose files, destinations, encryption, and retention.", kind: "operations", live: true },
            { id: "restore", aliases: ["restore", "recover", "recovery", "backup", "files", "browse"], title: "Restore files", description: "Browse a backup and recover individual files.", kind: "operations", live: true },
            { id: "snapshots", store: "Snapper root configuration and Btrfs snapshots", aliases: ["snapshots", "snapper", "system", "recovery", "create", "delete", "restore"], title: "System snapshots", description: "Configure snapshots and review recovery options.", kind: "operations", live: true }
        ] }
    ] },
    { id: "system", title: "System", icon: "󰒓", description: "Keep your desktop current and running well.", groups: [
        { title: "Maintenance", rows: [
            { id: "updates", store: "pacman package database / Blankweave release state", aliases: ["update", "upgrade", "release", "notes", "packages", "blankweave", "check"], title: "Updates & release notes", description: "Review Blankweave and package updates.", kind: "operations", live: true },
            { id: "firmware", store: "fwupd device firmware", aliases: ["firmware", "bios", "uefi", "device", "update", "upgrade"], title: "Device firmware", description: "Check for supported BIOS and peripheral updates.", kind: "operations", live: true },
            { id: "diagnostics", aliases: ["diagnostics", "health", "check", "report", "copy", "logs"], title: "Diagnostics", description: "Run read-only health checks and copy a local report.", kind: "system-info", live: true }
        ] },
        { title: "This computer", rows: [
            { id: "accounts", store: "system account database; /etc/blankweave/signin.conf", aliases: ["accounts", "users", "password", "sign", "in", "login", "create", "change", "delete", "administrator"], title: "Users & sign-in", description: "Manage accounts, passwords, and sign-in preferences.", kind: "operations", live: true },
            { id: "datetime", store: "system timezone / locale / timedated", aliases: ["timezone", "time", "zone", "clock", "date", "locale", "region", "language", "ntp", "synchronization", "formats"], title: "Date, time & region", description: "Choose a timezone, formats, and clock synchronization.", kind: "operations", live: true },
            { id: "printers", store: "CUPS printer configuration", aliases: ["printer", "scanner", "print", "scan", "devices", "jobs", "add", "remove"], title: "Printers & scanners", description: "Add devices and manage print jobs.", kind: "operations", live: true },
            { id: "about", aliases: ["about", "computer", "hardware", "software", "version", "support", "information"], title: "About this computer", description: "View hardware, software versions, and support information.", kind: "system-info", live: true }
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
    "sound-alerts": "system bell beep alert event sounds",
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

function searchSettings(query, capabilities) {
    var normalized = String(query || "").toLowerCase().trim();
    if (!normalized) return [];
    var terms = normalized.split(/\s+/);
    var matches = [];
    pages.forEach(function(page) {
        page.groups.forEach(function(group) {
            group.rows.forEach(function(row) {
                if (!available(row, capabilities)) return;
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

// null means detection could not be read: preserve access to all controls.
function available(row, capabilities) {
    return !row.requires || capabilities === null || capabilities === undefined || capabilities.includes(row.requires);
}
function visiblePages(capabilities) {
    return pages.map(function(page) {
        return Object.assign({}, page, {groups: page.groups.map(function(group) {
            return Object.assign({}, group, {rows: group.rows.filter(function(row) { return available(row, capabilities); })});
        }).filter(function(group) { return group.rows.length > 0; })});
    });
}
