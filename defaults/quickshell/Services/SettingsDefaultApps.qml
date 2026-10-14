import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property string helper: Quickshell.env("HOME") + "/.local/share/blankweave/shell/default-apps.py"
    property bool active: false
    property bool ready: false
    property bool canWrite: false
    property bool writing: false
    property string error: ""
    property string message: ""
    property string revision: ""
    property string context: ""
    property string request: ""
    property var rows: []
    readonly property bool busy: status.running || action.running || writing
    readonly property bool writable: ready && canWrite && !busy

    function refresh(clearError = false) {
        if (busy) return
        if (clearError) error = ""
        status.running = true
    }
    function apply(group, application, snapshot) {
        if (!writable) return
        const state = snapshot || {revision: revision, context: context}
        request = JSON.stringify({revision: state.revision, context: state.context, group: group, application: application})
        writing = true
        error = ""
        action.running = true
    }
    function snapshot() { return {revision: revision, context: context} }
    onActiveChanged: if (active) refresh(true)
    property Timer poll: Timer { interval: 5000; running: root.active; repeat: true; onTriggered: root.refresh() }
    property Process status: Process {
        command: ["python3", root.helper, "status"]
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: readError }
        onExited: (code, exitStatus) => {
            try {
                if (code !== 0 || exitStatus !== 0) throw new Error(readError.text.trim() || "Could not read default applications.")
                const data = JSON.parse(output.text)
                if (!Array.isArray(data.rows) || typeof data.revision !== "string" || typeof data.context !== "string"
                    || typeof data.writable !== "boolean" || typeof data.message !== "string"
                    || data.rows.some(r => typeof r.id !== "string" || typeof r.label !== "string" || typeof r.local !== "boolean"
                        || !Array.isArray(r.types) || r.types.some(t => typeof t !== "string")
                        || !Array.isArray(r.current) || r.current.some(a => ["type", "id", "name"].some(k => typeof a[k] !== "string"))
                        || !Array.isArray(r.choices) || r.choices.some(a => typeof a.id !== "string" || typeof a.name !== "string")))
                    throw new Error("Invalid default-app response.")
                root.rows = data.rows
                root.canWrite = data.writable
                root.message = data.message
                root.revision = data.revision
                root.context = data.context
                root.ready = true
            } catch (failure) { root.ready = false; root.rows = []; root.error = String(failure) }
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
            if (code !== 0 || exitStatus !== 0) root.error = writeError.text.trim() || "Could not change default applications."
            Qt.callLater(() => root.refresh())
        }
    }
}
