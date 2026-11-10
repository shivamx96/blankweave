import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property string helper: Quickshell.env("HOME") + "/.local/share/blankweave/shell/system-sounds.py"
    property bool active: false
    property bool ready: false
    property var preferences: ({})
    property var writable: ({})
    property var bell: ({available: false, writable: false, enabled: false, message: "System bell controls unavailable."})
    property var themes: []
    property bool gtkSynced: false
    property bool previewAvailable: false
    property string error: ""
    readonly property bool busy: status.running || action.running
    readonly property bool canPreview: ready && !busy && previewAvailable && preferences["event-sounds"] === true
        && themes.some(row => row.id === preferences["theme-name"])

    function refresh(clearError = false) {
        if (busy) return
        if (clearError) error = ""
        status.running = true
    }
    function apply(key, value) {
        if (!ready || busy || writable[key] !== true) return
        if (key === "theme-name" && !themes.some(row => row.id === value)) return
        execute(["set", key, String(value)])
    }
    function applyBell(enabled) {
        if (!ready || busy || !bell.writable) return
        execute(["set-bell", JSON.stringify({enabled: enabled, revision: bell.revision, session: bell.session, current: bell.current})])
    }
    function sync() { if (ready && !busy) execute(["sync"]) }
    function preview() { if (canPreview) execute(["preview"]) }
    function execute(arguments) {
        error = ""
        action.command = ["python3", helper].concat(arguments)
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
                if (code !== 0 || exitStatus !== 0) throw new Error(readError.text.trim() || "Could not read sound settings.")
                const data = JSON.parse(output.text)
                if (!data.preferences || typeof data.preferences["event-sounds"] !== "boolean"
                    || typeof data.preferences["input-feedback-sounds"] !== "boolean"
                    || typeof data.preferences["theme-name"] !== "string" || !Array.isArray(data.themes)
                    || !data.writable || typeof data.gtkSynced !== "boolean" || typeof data.previewAvailable !== "boolean")
                    throw new Error("Invalid sound settings response.")
                if (data.bell && (typeof data.bell.available !== "boolean" || typeof data.bell.writable !== "boolean"
                    || typeof data.bell.enabled !== "boolean" || typeof data.bell.message !== "string"
                    || (data.bell.writable && ["revision", "session", "current"].some(k => typeof data.bell[k] !== "string"))))
                    throw new Error("Invalid system bell response.")
                root.bell = data.bell || {available: false, writable: false, enabled: false, message: "Update the desktop helper to manage the system bell."}
                root.preferences = data.preferences
                root.writable = data.writable
                root.themes = data.themes.filter(row => typeof row.id === "string" && typeof row.name === "string")
                root.gtkSynced = data.gtkSynced
                root.previewAvailable = data.previewAvailable
                root.ready = true
            } catch (error) { root.ready = false; root.error = String(error) }
        }
    }
    property Process action: Process {
        stderr: StdioCollector { id: writeError }
        onExited: (code, exitStatus) => {
            if (code !== 0 || exitStatus !== 0)
                root.error = writeError.text.trim() || "Could not change sound settings. Try again."
            Qt.callLater(() => root.refresh())
        }
    }
}
