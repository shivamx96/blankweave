import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property string helper: Quickshell.env("HOME") + "/.local/share/blankweave/shell/night-light.py"
    property var preferences: ({ mode: "off", temperature: 4500, start: "21:00", end: "07:00" })
    property bool ready: false
    property bool available: false
    property bool reading: false
    property bool saving: false
    property bool restarting: false
    property string revision: ""
    property string attemptedRevision: ""
    property string error: ""
    property int actualTemperature: -1
    property var identity: null
    readonly property bool running: daemon.running
    readonly property bool busy: saving || restarting
    readonly property string description: error || (!available ? "Install hyprsunset to enable night light."
        : preferences.mode === "off" ? "Off. Applies to all connected displays."
        : !running || actualTemperature < 0 ? "Starting night light…"
        : identity === true ? "Scheduled; normal colors are active now."
        : "Active at " + actualTemperature + " K on all displays.")

    function refresh() {
        if (reading || saving) return
        reading = true
        status.running = true
    }
    function retry() { attemptedRevision = ""; error = ""; refresh() }
    function apply(mode, temperature, start, end) {
        if (!ready || busy) return
        saving = true
        error = ""
        writer.command = ["python3", helper, "set", mode, String(temperature), start, end]
        writer.running = true
    }
    function syncDaemon() {
        const wanted = available && preferences.mode !== "off"
        if (!wanted && !daemon.running) attemptedRevision = ""
        if (daemon.running && (!wanted || attemptedRevision !== revision)) {
            restarting = true
            daemon.signal(15)
        } else if (!daemon.running && wanted && attemptedRevision !== revision) {
            attemptedRevision = revision
            daemon.running = true
        }
    }
    Component.onCompleted: refresh()
    property Timer poll: Timer { interval: 3000; running: true; repeat: true; onTriggered: root.refresh() }
    property Process status: Process {
        command: ["python3", root.helper, "status"]
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: statusError }
        onExited: (code, status) => {
            root.reading = false
            try {
                if (code !== 0 || status !== 0) throw new Error(statusError.text.trim() || "Could not read night-light settings")
                const data = JSON.parse(output.text)
                if (!data.preferences || !["off", "always", "schedule"].includes(data.preferences.mode)
                    || !Number.isFinite(data.preferences.temperature) || typeof data.preferences.start !== "string"
                    || typeof data.preferences.end !== "string" || typeof data.revision !== "string"
                    || typeof data.available !== "boolean" || !Number.isFinite(data.temperature)) throw new Error("Invalid night-light status")
                root.preferences = data.preferences
                root.available = data.available
                root.revision = data.revision
                root.actualTemperature = data.temperature
                root.identity = data.identity
                root.ready = true
                root.syncDaemon()
            } catch (error) { root.ready = false; root.error = String(error) }
        }
    }
    property Process writer: Process {
        stderr: StdioCollector { id: writeError }
        onExited: (code, status) => {
            root.saving = false
            if (code !== 0 || status !== 0) root.error = writeError.text.trim() || "Could not save night light"
            root.refresh()
        }
    }
    property Process daemon: Process {
        command: ["python3", root.helper, "run"]
        stderr: StdioCollector { id: daemonError }
        stdout: StdioCollector { id: daemonOutput }
        onExited: (code, status) => {
            if (root.restarting) {
                root.restarting = false
                root.syncDaemon()
            } else {
                root.error = daemonError.text.trim() || daemonOutput.text.trim() || "Night light stopped. Retry to start it again."
            }
            root.refresh()
        }
    }
}
