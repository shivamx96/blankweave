import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property string helper: Quickshell.env("HOME") + "/.local/share/blankweave/shell/pointer-settings.py"
    property bool active: false
    property bool ready: false
    property bool installed: false
    property bool synced: false
    property bool writing: false
    property string error: ""
    property string message: ""
    property string revision: ""
    property string session: ""
    property string request: ""
    property var saved: ({global: {}, touchpad: {}, devices: {}})
    property var values: ({global: {}, touchpad: {}})
    property var devices: []
    readonly property bool busy: status.running || action.running || writing
    readonly property var globalFields: ["sensitivity", "accel_profile", "natural_scroll", "left_handed"]
    readonly property var touchpadFields: ["natural_scroll", "tap_to_click", "disable_while_typing"]

    function refresh(clearError = false) {
        if (busy) return
        if (clearError) error = ""
        status.running = true
    }
    function fields(target) {
        if (!target || !["global", "touchpad", "device"].includes(target.scope)) return []
        if (target.scope === "touchpad") return touchpadFields
        return target.scope === "device" && target.kind === "touchpad"
            ? globalFields.concat(["tap_to_click", "disable_while_typing"]) : globalFields
    }
    function writable(target) {
        return target && ["global", "touchpad", "device"].includes(target.scope)
            && ready && installed && synced && !busy && (target.scope !== "device"
            || devices.some(row => row.name === target.name && row.address === target.address && row.unique))
    }
    function value(target, key) {
        if (!ready || !target || !["global", "touchpad", "device"].includes(target.scope)) return null
        if (target.scope !== "device") return values[target.scope][key]
        const row = saved.devices[target.name] || {}
        return row[key] === undefined ? null : row[key]
    }
    function overridden(target, key) {
        if (!target || !["global", "touchpad", "device"].includes(target.scope)) return false
        const row = target.scope === "device" ? saved.devices[target.name] || {} : saved[target.scope]
        return row && row[key] !== undefined
    }
    function choices(target, key) {
        let options
        if (key === "sensitivity") {
            options = [-1, -0.75, -0.5, -0.25, 0, 0.25, 0.5, 0.75, 1].map(v => ({value: v, label: (v > 0 ? "+" : "") + v.toFixed(2)}))
            const current = value(target, key)
            if (current !== null && !options.some(row => row.value === current))
                options.push({value: current, label: String(current) + " (current)"})
        } else if (key === "accel_profile") {
            options = [{value: "", label: "Device default"}, {value: "adaptive", label: "Adaptive"}, {value: "flat", label: "Flat"}]
            const current = value(target, key)
            if (current !== null && !options.some(row => row.value === current))
                options.push({value: current, label: "Custom (current)"})
        } else options = [{value: false, label: "Off"}, {value: true, label: "On"}]
        if (target && target.scope === "device") options.unshift({value: null, label: "No saved override"})
        return options
    }
    function apply(target, key, value) {
        if (!writable(target)) { error = "The selected device or settings changed. Refresh and try again."; return }
        request = JSON.stringify({revision: revision, session: session, scope: target.scope,
            device: target.name || "", address: target.address || "", key: key, value: value})
        writing = true
        error = ""
        action.running = true
    }
    onActiveChanged: if (active) refresh(true)
    property Timer poll: Timer { interval: 5000; running: root.active; repeat: true; onTriggered: root.refresh() }
    property Process status: Process {
        command: ["python3", root.helper, "status"]
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: readError }
        onExited: (code, exitStatus) => {
            try {
                if (code !== 0 || exitStatus !== 0) throw new Error(readError.text.trim() || "Could not read pointer settings.")
                const data = JSON.parse(output.text)
                if (!data.saved || !data.saved.global || !data.saved.touchpad || !data.saved.devices
                    || !data.values || !data.values.global || !data.values.touchpad || !Array.isArray(data.devices)
                    || typeof data.revision !== "string" || typeof data.session !== "string"
                    || typeof data.installed !== "boolean" || typeof data.synced !== "boolean" || typeof data.message !== "string"
                    || data.devices.some(d => typeof d.name !== "string" || typeof d.address !== "string"
                        || !["pointer", "mouse", "touchpad"].includes(d.kind) || typeof d.unique !== "boolean")
                    || typeof data.values.global.sensitivity !== "number" || !Number.isFinite(data.values.global.sensitivity)
                    || typeof data.values.global.accel_profile !== "string"
                    || ["natural_scroll", "left_handed"].some(k => typeof data.values.global[k] !== "boolean")
                    || root.touchpadFields.some(k => typeof data.values.touchpad[k] !== "boolean"))
                    throw new Error("Invalid pointer settings response.")
                root.saved = data.saved
                root.values = data.values
                root.devices = data.devices
                root.installed = data.installed
                root.synced = data.synced
                root.message = data.message
                root.revision = data.revision
                root.session = data.session
                root.ready = true
            } catch (failure) { root.ready = false; root.devices = []; root.error = String(failure) }
        }
    }
    property Process action: Process {
        command: ["python3", root.helper, "apply"]
        stdinEnabled: true
        onStarted: { write(root.request); stdinEnabled = false }
        stderr: StdioCollector { id: writeError }
        onExited: (code, exitStatus) => {
            root.writing = false
            stdinEnabled = true
            if (code !== 0 || exitStatus !== 0) root.error = writeError.text.trim() || "Could not change pointer settings."
            Qt.callLater(() => root.refresh())
        }
    }
}
