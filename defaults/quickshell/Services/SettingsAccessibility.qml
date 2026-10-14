import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property string helper: Quickshell.env("HOME") + "/.local/share/blankweave/shell/accessibility-settings.py"
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
    property var saved: ({reduced_motion: false, high_contrast: false})
    property var desktop: ({reduced_motion: false, high_contrast: false})
    readonly property bool busy: status.running || action.running || writing
    readonly property bool writable: ready && installed && synced && !busy

    function refresh(clearError = false) {
        if (busy) return
        if (clearError) error = ""
        status.running = true
    }
    function apply(key, value, snapshot) {
        if (!writable) return
        const state = snapshot || {revision: revision, session: session, desktop: desktop}
        request = JSON.stringify({revision: state.revision, session: state.session, desktop: state.desktop,
            key: key, value: value})
        writing = true
        error = ""
        action.running = true
    }
    function snapshot() { return {revision: revision, session: session, desktop: Object.assign({}, desktop)} }
    onActiveChanged: if (active) refresh(true)
    property Timer poll: Timer { interval: 5000; running: root.active; repeat: true; onTriggered: root.refresh() }
    property Process status: Process {
        command: ["python3", root.helper, "status"]
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: readError }
        onExited: (code, exitStatus) => {
            try {
                if (code !== 0 || exitStatus !== 0) throw new Error(readError.text.trim() || "Could not read accessibility settings.")
                const data = JSON.parse(output.text)
                if (!data.saved || !data.desktop
                    || typeof data.revision !== "string" || typeof data.session !== "string"
                    || typeof data.installed !== "boolean" || typeof data.synced !== "boolean"
                    || ["reduced_motion", "high_contrast"].some(k => typeof data.saved[k] !== "boolean" || typeof data.desktop[k] !== "boolean")
                    || typeof data.desktop.compositor_motion !== "boolean")
                    throw new Error("Invalid accessibility settings response.")
                root.saved = data.saved
                root.desktop = data.desktop
                root.installed = data.installed
                root.synced = data.synced
                root.message = data.synced ? "" : "Reload or update the desktop to load saved accessibility settings."
                root.revision = data.revision
                root.session = data.session
                root.ready = true
            } catch (failure) { root.ready = false; root.error = String(failure) }
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
            if (code !== 0 || exitStatus !== 0) root.error = writeError.text.trim() || "Could not change accessibility settings."
            Qt.callLater(() => root.refresh())
        }
    }
}
