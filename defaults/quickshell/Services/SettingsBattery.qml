import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property string helper: Quickshell.env("HOME") + "/.local/share/blankweave/shell/battery-health.py"
    property bool active: false
    property bool ready: false
    property bool available: false
    property var batteries: []
    property string error: ""
    property string pending: ""
    property bool verifying: false
    readonly property bool busy: status.running || action.running || verifying

    function refresh(clearError = false) {
        if (busy) return
        if (clearError) error = ""
        status.running = true
    }
    function setLimit(row, enabled) {
        if (!ready || busy || !row.supported || typeof enabled !== "boolean") return
        if (!batteries.some(current => current.owner === row.owner && current.path === row.path && current.identity === row.identity)) {
            error = "The battery changed. Refresh and try again."
            return
        }
        if (row.enabled === enabled) return
        error = ""; verifying = true
        pending = JSON.stringify({owner: row.owner, path: row.path, identity: row.identity, enabled: enabled})
        action.running = true
    }
    onActiveChanged: if (active) refresh(true)
    property Timer poll: Timer { interval: 10000; running: root.active; repeat: true; onTriggered: root.refresh() }
    property Process status: Process {
        command: ["python3", root.helper, "status"]
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: readError }
        onExited: (code, exitStatus) => {
            try {
                if (code !== 0 || exitStatus !== 0) throw new Error(readError.text.trim() || "Could not read battery information.")
                const data = JSON.parse(output.text)
                if (typeof data.available !== "boolean" || !Array.isArray(data.batteries) || data.batteries.some(row => !row
                    || ["path", "owner", "identity", "name", "vendor", "state"].some(key => typeof row[key] !== "string")
                    || typeof row.supported !== "boolean" || typeof row.firmware !== "boolean"
                    || (row.enabled !== null && typeof row.enabled !== "boolean")
                    || (row.supported && typeof row.enabled !== "boolean")
                    || ["charge", "health", "energyFull", "energyDesign", "cycles", "start", "end"].some(key => row[key] !== null && (typeof row[key] !== "number" || !Number.isFinite(row[key]) || row[key] < 0))))
                    throw new Error("Invalid battery information response.")
                if (!root.ready) root.error = ""
                root.available = data.available; root.batteries = data.batteries; root.ready = true
            } catch (error) {
                root.ready = false; root.available = false; root.batteries = []; root.error = String(error)
            }
            root.verifying = false
        }
    }
    property Process action: Process {
        command: ["python3", root.helper, "set"]
        stdinEnabled: true
        onStarted: { write(root.pending + "\n"); stdinEnabled = false }
        stderr: StdioCollector { id: writeError }
        onExited: (code, exitStatus) => {
            if (code !== 0 || exitStatus !== 0) root.error = writeError.text.trim() || "Could not change the battery charge limit."
            root.pending = ""; stdinEnabled = true
            // Finish verification even when Settings was closed during the write.
            root.status.running = true
        }
    }
}
