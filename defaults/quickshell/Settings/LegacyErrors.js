.pragma library

// Older service adapters still expose a string. Never use that string as the
// primary line; new task adapters already supply a trusted message and detail.
function message(value) {
    if (!value) return "";
    const raw = String(value).replace(/^Error:\s*/, "");
    const lower = raw.toLowerCase();
    if (/cancelled|canceled|dismissed/.test(lower)) return "";
    if (/wrong password|incorrect password|authentication failed|secrets were required/.test(lower)) return "The password was not accepted.";
    if (/no longer in range|access point not found/.test(lower)) return "That network is no longer in range.";
    if (/networkmanager/.test(lower)) return "Could not reach NetworkManager.";
    if (/override/.test(lower)) return "Another setting overrides this change. Review your personal configuration.";
    if (/changed|stale|disconnected|no longer available/.test(lower)) return "These settings changed. Refresh and try again.";
    if (/^(Enter a valid |Passwords do not match\.|Another change is in progress\.)/.test(raw)) return raw;
    return "Could not apply this change. Try again.";
}
function detail(value) {
    let raw = String(value || "").replace(/^Error:\s*/, "");
    if (/cancelled|canceled|dismissed/i.test(raw)) return "";
    if (raw.indexOf("Traceback (most recent call last)") >= 0) raw = raw.split("\n").pop();
    return raw.replace(/\/home\/[^\s/]+(?:\/[^\s"']*)?|\/root(?:\/[^\s"']*)?/g, "~")
        .replace(/(password|passwd|token|secret|psk|credential)(\s*[=:]\s*)[^\s,;]+/gi, "$1$2[redacted]").slice(0,4000);
}
