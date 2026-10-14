import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property string helper: Quickshell.env("HOME") + "/.local/share/blankweave/shell/keyboard-settings.py"
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
    property var saved: ({values: {}})
    property var values: ({})
    property var devices: []
    property var catalog: []
    property string actionName: "apply"
    readonly property bool busy: status.running || action.running || writing
    readonly property bool writable: ready && installed && synced && !busy && !values.kb_file
        && ["", "evdev", "base"].includes(values.kb_rules)

    function refresh(clearError = false) {
        if (busy) return
        if (clearError) error = ""
        status.running = true
    }
    function run(name, payload) {
        if (!ready || busy) return
        actionName = name
        request = JSON.stringify(payload)
        writing = true
        error = ""
        action.running = true
    }
    function apply(layouts, options, expected, token, desktop) {
        if (!writable) return
        run("apply", {revision: token, session: desktop, expected: expected,
            values: layouts === null ? {} : {kb_layout: layouts.map(r => r.layout).join(","),
                kb_variant: layouts.map(r => r.variant).join(","), kb_options: options}})
    }
    function switchLayout(device, index) {
        run("switch", {session: session, device: device.name, address: device.address,
            layout: device.layout, variant: device.variant, index: index})
    }
    onActiveChanged: if (active) refresh(true)
    property Timer poll: Timer { interval: 5000; running: root.active; repeat: true; onTriggered: root.refresh() }
    property Process status: Process {
        command: ["python3", root.helper, "status"]
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: readError }
        onExited: (code, exitStatus) => {
            try {
                if (code !== 0 || exitStatus !== 0) throw new Error(readError.text.trim() || "Could not read keyboard settings.")
                const data = JSON.parse(output.text)
                if (!data.saved || !data.saved.values || !data.values || !Array.isArray(data.devices)
                    || !Array.isArray(data.catalog) || typeof data.revision !== "string" || typeof data.session !== "string"
                    || typeof data.installed !== "boolean" || typeof data.synced !== "boolean" || typeof data.message !== "string"
                    || ["kb_layout", "kb_variant", "kb_options", "kb_file", "kb_rules", "kb_model"].some(k => typeof data.values[k] !== "string")
                    || data.devices.some(d => ["name", "address", "layout", "variant", "active_keymap"].some(k => typeof d[k] !== "string"))
                    || data.catalog.some(d => ["layout", "variant", "label"].some(k => typeof d[k] !== "string")))
                    throw new Error("Invalid keyboard settings response.")
                root.catalog = data.catalog
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
        command: ["python3", root.helper, root.actionName]
        stdinEnabled: true
        onStarted: { write(root.request); stdinEnabled = false }
        stderr: StdioCollector { id: writeError }
        onExited: (code, exitStatus) => {
            root.writing = false
            stdinEnabled = true
            if (code !== 0 || exitStatus !== 0) root.error = writeError.text.trim() || "Could not change keyboard settings."
            Qt.callLater(() => root.refresh())
        }
    }
}
