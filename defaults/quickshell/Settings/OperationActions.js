.pragma library

// Explicit task priorities keep destructive operations out of the primary slot.
var priorities = {
    "vpn": ["connect", "import", "tailscale-login"],
    "sharing": ["share", "setup", "nearby"],
    "hibernate": ["idle", "policy"],
    "assistive": ["reader", "keyboard", "zoom"],
    "installed": ["search", "inventory"],
    "permissions": ["inspect"],
    "disk-usage": ["scan"],
    "drives": ["mount"],
    "disk-health": ["health"],
    "backup": ["backup", "configure"],
    "restore": ["list", "browse"],
    "snapshots": ["list", "setup"],
    "updates": ["check", "package-check", "release-notes"],
    "firmware": ["check"],
    "accounts": ["create"],
    "datetime": ["timezone"],
    "printers": ["add", "scanners"]
};

// Only these read-only operations can skip the form. Unknown/new actions retain
// their input/confirmation step. A choice with one option needs no extra picker.
var directReads = {
    "disk-usage": ["preview-cleanup"],
    "disk-health": ["health"],
    "installed": ["inventory", "flatpak-list"],
    "permissions": ["inspect"],
    "restore": ["list"],
    "snapshots": ["list"],
    "updates": ["check", "release-notes", "package-check"],
    "printers": ["scanners"]
};

function primary(settingId, actions) {
    var keys = priorities[settingId] || [];
    for (var i = 0; i < keys.length; i++) {
        var found = actions.find(function(action) { return action.key === keys[i]; });
        if (found) return found;
    }
    return null;
}

function direct(settingId, action) {
    return Boolean(action && !action.confirm && (directReads[settingId] || []).includes(action.key)
        && action.fields.every(function(field) {
            return !field.secret && field.options.length === 1 && field.value === field.options[0].value;
        }));
}

function label(settingId, action) {
    if (!action) return "";
    if (settingId === "backup" && action.key === "configure") return "Set up backups…";
    return action.label + (direct(settingId, action) ? "" : "…");
}
