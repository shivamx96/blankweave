import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property string helper: Quickshell.env("HOME") + "/.local/share/blankweave/shell/shortcuts-settings.py"
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
    property var rows: []
    property var keys: []
    property var other: []
    property string fingerprint: ""
    readonly property bool busy: status.running || action.running || writing
    readonly property bool writable: ready && installed && synced && !busy

    function refresh(clearError = false) {
        if (busy) return
        if (clearError) error = ""
        status.running = true
    }
    function apply(id, value, token, desktop, live) {
        if (!writable) return
        request = JSON.stringify({id: id, value: value, revision: token, session: desktop, fingerprint: live})
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
                if (code !== 0 || exitStatus !== 0) throw new Error(readError.text.trim() || "Could not read shortcuts settings.")
                const data = JSON.parse(output.text)
                if (!Array.isArray(data.rows) || !Array.isArray(data.keys) || !Array.isArray(data.other)
                    || typeof data.revision !== "string" || typeof data.session !== "string" || typeof data.fingerprint !== "string"
                    || typeof data.installed !== "boolean" || typeof data.synced !== "boolean" || typeof data.message !== "string"
                    || data.rows.some(r => ["id", "label", "group", "default", "value"].some(k => typeof r[k] !== "string")
                        || typeof r.available !== "boolean" || typeof r.overridden !== "boolean")
                    || data.keys.some(k => typeof k !== "string")
                    || data.other.some(r => typeof r.key !== "string" || typeof r.description !== "string" || typeof r.submap !== "string" || typeof r.modmask !== "number"))
                    throw new Error("Invalid shortcut settings response.")
                root.rows = data.rows
                root.keys = data.keys
                root.other = data.other
                root.fingerprint = data.fingerprint
                root.installed = data.installed
                root.synced = data.synced
                root.message = data.message
                root.revision = data.revision
                root.session = data.session
                root.ready = true
            } catch (failure) { root.ready = false; root.rows = []; root.other = []; root.error = String(failure) }
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
            if (code !== 0 || exitStatus !== 0) root.error = writeError.text.trim() || "Could not change shortcuts settings."
            Qt.callLater(() => root.refresh())
        }
    }
}
