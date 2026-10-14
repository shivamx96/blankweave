import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property string helper: Quickshell.env("HOME") + "/.local/share/blankweave/shell/interface-settings.py"
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
    property var saved: ({text_scale: 1, cursor_size: 24})
    property var desktop: ({text_scale: 1, cursor_size: 24})
    property string cursorTheme: ""
    readonly property bool busy: status.running || action.running || writing
    readonly property bool writable: ready && installed && synced && !busy

    function refresh(clearError = false) {
        if (busy) return
        if (clearError) error = ""
        status.running = true
    }
    function apply(key, value, snapshot) {
        if (!writable) return
        const state = snapshot || {revision: revision, session: session, desktop: desktop, theme: cursorTheme}
        request = JSON.stringify({revision: state.revision, session: state.session, desktop: state.desktop,
            theme: state.theme, key: key, value: value})
        writing = true
        error = ""
        action.running = true
    }
    function snapshot() { return {revision: revision, session: session, desktop: Object.assign({}, desktop), theme: cursorTheme} }
    onActiveChanged: if (active) refresh(true)
    property Timer poll: Timer { interval: 5000; running: root.active; repeat: true; onTriggered: root.refresh() }
    property Process status: Process {
        command: ["python3", root.helper, "status"]
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: readError }
        onExited: (code, exitStatus) => {
            try {
                if (code !== 0 || exitStatus !== 0) throw new Error(readError.text.trim() || "Could not read interface settings.")
                const data = JSON.parse(output.text)
                if (!data.saved || !data.desktop || typeof data.theme !== "string"
                    || typeof data.revision !== "string" || typeof data.session !== "string"
                    || typeof data.installed !== "boolean" || typeof data.synced !== "boolean"
                    || ![1, 1.15, 1.3].includes(data.saved.text_scale) || ![24, 32, 48].includes(data.saved.cursor_size)
                    || ["text_scale", "cursor_size"].some(k => typeof data.desktop[k] !== "number" || !Number.isFinite(data.desktop[k]) || data.desktop[k] <= 0))
                    throw new Error("Invalid interface settings response.")
                root.saved = data.saved
                root.desktop = data.desktop
                root.cursorTheme = data.theme
                root.installed = data.installed
                root.synced = data.synced
                root.message = data.synced ? "" : "Reload or update the desktop to load saved interface settings."
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
            if (code !== 0 || exitStatus !== 0) root.error = writeError.text.trim() || "Could not change interface settings."
            Qt.callLater(() => root.refresh())
        }
    }
}
