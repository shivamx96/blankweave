.pragma library

function key(request) {
    return JSON.stringify([request.control || request.action || "value", request.id || request.app || ""]);
}

// null means the helper has no observable target contract. Only that case may
// use the old baseline fallback. A known but unsatisfied target returns false.
function observed(script, request, data, baseline) {
    const rows = data.rows || [];
    const row = rows.find(r => r.id === request.id);
    if (script === "startup-settings.py") {
        if (!row) return true;
        if (request.action === "enable") return row.enabled === request.enabled;
        if (request.action === "reset") return !row.reset;
    }
    if (script === "wallpaper-settings.py") {
        if (!row) return true;
        if (request.action === "reset") return !row.custom && row.current === row.path;
        if (request.action === "set") return row.custom && row.path === request.path && row.current === row.path && row.fit === request.fit;
    }
    if (script === "webapps-settings.py") {
        if (request.action === "remove") return !row;
        if (request.action === "create") {
            const id = request.name.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
            return rows.some(r => r.id === id && r.name === request.name.trim() && r.url === request.url);
        }
    }
    if (script === "notification-settings.py") {
        const policy = data.policy || {};
        if (request.action === "manual") return data.paused === request.value && policy.manual === request.value;
        if (request.action === "schedule") return policy.schedule === request.enabled && policy.start === request.start && policy.end === request.end;
        if (request.action === "app") return !(data.apps || []).includes(request.app) || (policy.blocked || []).includes(request.app) === request.blocked;
    }
    if (script === "system-settings.py" && request.action === "diagnose")
        return Boolean(data.report && JSON.stringify(data.report) !== JSON.stringify(baseline.report));
    // Generic scalar tasks (including the isolated fixture).
    if (!request.action && Object.hasOwnProperty.call(request, "value") && Object.hasOwnProperty.call(data, "value"))
        return data.value === request.value;
    return null;
}

// Operation forms may contain credentials. Their fallback reconciliation needs
// only the action identity, never the form values or authentication material.
function capture(script, request) {
    if (["startup-settings.py", "wallpaper-settings.py", "webapps-settings.py", "notification-settings.py", "system-settings.py"].includes(script))
        return Object.assign({}, request);
    const result = {action: request.action, id: request.id, app: request.app, control: request.control};
    if (typeof request.value === "boolean" || typeof request.value === "number") result.value = request.value;
    return result;
}
