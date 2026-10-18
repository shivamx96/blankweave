import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    required property string script
    property string helper: Quickshell.env("HOME") + "/.local/share/blankweave/shell/" + script
    property var arguments: []
    property bool active: false
    property bool ready: false
    property bool writing: false
    property string error: ""
    property var data: ({})
    property string request: ""
    signal applyFinished(bool success, var result)
    readonly property bool busy: writing || status.running || action.running
    readonly property bool writable: ready && !busy && data.writable !== false
    function refresh(clearError = false) {
        if (busy) return
        if (clearError) error = ""
        status.running = true
    }
    function apply(options, revision) {
        if (!writable) return
        request = JSON.stringify(Object.assign({}, options, {revision: revision || data.revision}))
        writing = true; error = ""; action.running = true
    }
    function cancelJob(id) {
        if (busy) return
        request = JSON.stringify({action: "cancel-job", id: id})
        writing = true; error = ""; action.running = true
    }
    onActiveChanged: if (active) refresh(true)
    property Timer poll: Timer { interval: 5000; repeat: true; running: root.active; onTriggered: root.refresh() }
    property Process status: Process {
        command: ["python3", root.helper].concat(root.arguments, ["status"])
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: readError }
        onExited: (code, exitStatus) => {
            try {
                if (code || exitStatus) throw new Error(readError.text.trim() || "Could not read settings.")
                const value = JSON.parse(output.text)
                if (!value || typeof value.revision !== "string") throw new Error("Invalid settings response.")
                root.data = value; root.ready = true
            } catch (failure) { root.ready = false; root.error = String(failure) }
        }
    }
    property Process action: Process {
        command: ["python3", root.helper].concat(root.arguments, ["apply"])
        stdinEnabled: true
        onStarted: { write(root.request); root.request = ""; stdinEnabled = false }
        stderr: StdioCollector { id: writeError }
        stdout: StdioCollector { id: writeResult }
        onExited: (code, exitStatus) => {
            root.writing = false; stdinEnabled = true
            if (code || exitStatus) root.error = writeError.text.trim() || "Could not apply settings."
            let result = null
            try { result = JSON.parse(writeResult.text) } catch (_) { }
            root.applyFinished(!code && !exitStatus, result)
            Qt.callLater(() => root.refresh())
        }
    }
}
