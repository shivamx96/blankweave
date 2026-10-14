import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property string helper: Quickshell.env("HOME") + "/.local/share/blankweave/shell/idle-policy.py"
    property bool active: false
    property bool ready: false
    property bool managed: false
    property bool running: false
    property bool applied: false
    property bool battery: false
    property string source: ""
    property string message: ""
    property string revision: ""
    property string pendingRequest: ""
    property var settings: ({})
    property string error: ""
    property bool writing: false
    readonly property bool busy: status.running || action.running || writing
    readonly property var delays: [0, 60, 120, 150, 300, 360, 600, 900, 1800, 3600, 7200]
    readonly property var labels: ["Never", "1 minute", "2 minutes", "2½ minutes", "5 minutes", "6 minutes", "10 minutes", "15 minutes", "30 minutes", "1 hour", "2 hours"]

    function refresh(clearError = false) {
        if (busy) return
        if (clearError) error = ""
        status.running = true
    }
    function apply(mode, key, seconds) {
        if (!ready || busy || !managed || !running || !["ac", "battery"].includes(mode)
            || !["dim", "lock", "screen", "suspend"].includes(key) || !delays.includes(seconds)) return
        const updated = JSON.parse(JSON.stringify(settings))
        updated[mode][key] = seconds
        pendingRequest = JSON.stringify({revision: revision, settings: updated})
        error = ""
        writing = true
        action.running = true
    }
    onActiveChanged: if (active) refresh(true)
    property Timer poll: Timer { interval: 3000; running: root.active; repeat: true; onTriggered: root.refresh() }
    property Process status: Process {
        command: ["python3", root.helper, "status"]
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: readError }
        onExited: (code, exitStatus) => {
            try {
                if (code !== 0 || exitStatus !== 0) throw new Error(readError.text.trim() || "Could not read idle settings.")
                const data = JSON.parse(output.text)
                if (!data.settings || data.settings.version !== 1 || typeof data.revision !== "string"
                    || typeof data.message !== "string" || !["ac", "battery"].includes(data.source)
                    || ["managed", "running", "applied", "battery"].some(key => typeof data[key] !== "boolean")
                    || ["ac", "battery"].some(mode => !data.settings[mode]
                        || ["dim", "lock", "screen", "suspend"].some(key => !root.delays.includes(data.settings[mode][key]))))
                    throw new Error("Invalid idle settings response.")
                root.settings = data.settings
                root.revision = data.revision
                root.managed = data.managed
                root.running = data.running
                root.applied = data.applied
                root.battery = data.battery
                root.source = data.source
                root.message = data.message
                root.ready = true
            } catch (error) { root.ready = false; root.error = String(error) }
        }
    }
    property Process action: Process {
        command: ["python3", root.helper, "configure"]
        stdinEnabled: true
        onStarted: { write(root.pendingRequest); stdinEnabled = false }
        stderr: StdioCollector { id: writeError }
        onExited: (code, exitStatus) => {
            root.writing = false
            stdinEnabled = true
            if (code !== 0 || exitStatus !== 0)
                root.error = writeError.text.trim() || "Could not save idle settings."
            Qt.callLater(() => root.refresh())
        }
    }
}
