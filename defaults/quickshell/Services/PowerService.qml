import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property string helper: Quickshell.env("HOME") + "/.local/share/blankweave/shell/power-profiles.py"
    property bool settingsActive: false
    property bool menuOpen: false
    property var owners: []
    readonly property bool active: settingsActive || owners.length > 0
    property bool ready: false
    property bool available: false
    property string service: ""
    property string owner: ""
    property string profile: ""
    property var profiles: []
    property string degraded: ""
    property var holds: []
    property string error: ""
    property bool verifying: false
    readonly property bool busy: status.running || action.running || verifying
    readonly property string profileName: profiles.find(row => row.id === profile)?.name || "Unknown"
    readonly property string degradation: degraded === "high-operating-temperature"
        ? "Performance is limited because the system is running hot."
        : degraded === "lap-detected" ? "Performance is limited while the laptop is on your lap."
        : degraded ? "The system is temporarily limiting performance." : ""
    readonly property string explanation: !ready ? "Reading power profiles…"
        : !available ? "Power profiles are unavailable. Install and enable power-profiles-daemon on supported hardware."
        : profiles.length === 0 ? "The power service reports no supported profiles."
        : "Active profile: " + profileName

    function setActive(view, value) {
        const next = owners.filter(item => item !== view)
        if (value) next.push(view)
        owners = next
    }
    function refresh(clearError = false) {
        if (busy || menuOpen) return
        if (clearError) error = ""
        status.running = true
    }
    function canSelect(id) { return ready && available && !busy && profiles.some(row => row.id === id) }
    function select(id, capturedService = service, capturedOwner = owner) {
        if (!canSelect(id)) return
        if (service !== capturedService || owner !== capturedOwner) {
            error = "The power service changed. Refresh and choose a profile again."
            return
        }
        if (profile === id) return
        error = ""
        verifying = true
        action.command = ["python3", helper, "set", capturedService, capturedOwner, id]
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
                if (code !== 0 || exitStatus !== 0) throw new Error(readError.text.trim() || "Could not read power profiles.")
                const data = JSON.parse(output.text)
                if (typeof data.available !== "boolean"
                    || ["service", "owner", "profile", "degraded"].some(key => typeof data[key] !== "string")
                    || !Array.isArray(data.profiles) || data.profiles.some(row => !row || typeof row.id !== "string" || typeof row.name !== "string")
                    || !Array.isArray(data.holds) || data.holds.some(row => !row || ["application", "profile", "reason"].some(key => typeof row[key] !== "string"))
                    || (data.available && (!data.owner.startsWith(":") || !data.service || !data.profile)))
                    throw new Error("Invalid power profile response.")
                root.available = data.available
                root.service = data.service; root.owner = data.owner
                root.profile = data.profile; root.profiles = data.profiles
                root.degraded = data.degraded; root.holds = data.holds
                root.ready = true
            } catch (error) {
                root.ready = false; root.available = false
                root.profiles = []; root.profile = ""; root.holds = []; root.degraded = ""
                root.error = String(error)
            }
            root.verifying = false
        }
    }
    property Process action: Process {
        stderr: StdioCollector { id: writeError }
        onExited: (code, exitStatus) => {
            if (code !== 0 || exitStatus !== 0) root.error = writeError.text.trim() || "Could not change the power profile."
            root.verifying = true
            // Always read back, including after failure or after the last view closes.
            root.status.running = true
        }
    }
}
