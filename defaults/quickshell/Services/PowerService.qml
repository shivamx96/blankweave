import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property string helper: Quickshell.env("HOME") + "/.local/share/blankweave/shell/power-profiles.py"
    property bool settingsActive: false
    property bool menuOpen: false
    property bool automaticMenuOpen: false
    property int automaticInterval: 10000
    property var automatic: ({ready: false, settings: {enabled: false}, source: {available: false}, message: "Loading automatic profiles…"})
    property string automaticSaveError: ""
    property string automaticRunError: ""
    readonly property string automaticError: automaticSaveError || automaticRunError
    property string actionKind: ""
    property string pendingConfig: ""
    property bool tickAfterRead: true
    readonly property bool automaticEnabled: automatic.ready && automatic.settings.enabled
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
        if (busy || menuOpen || automaticMenuOpen) return
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
        if (profile === id && !automaticEnabled) return
        error = ""; automaticSaveError = ""; automaticRunError = ""
        verifying = true
        actionKind = "manual"
        action.command = ["python3", helper, "set", capturedService, capturedOwner, id]
        action.running = true
    }
    function configureAutomatic(changes) {
        if (busy || !automatic.ready) return
        pendingConfig = JSON.stringify({expected: automatic.settings, settings: Object.assign({}, automatic.settings, changes)})
        error = ""; automaticSaveError = ""; automaticRunError = ""; verifying = true
        actionKind = "configure"
        action.command = ["python3", helper, "auto-configure"]
        action.running = true
    }
    function tick() {
        if (!automaticEnabled || busy || menuOpen || automaticMenuOpen) return
        verifying = true; actionKind = "automatic"
        action.command = ["python3", helper, "auto-tick"]
        action.running = true
    }
    Component.onCompleted: refresh()
    onActiveChanged: if (active) refresh(true)
    property Timer automation: Timer {
        interval: root.automaticInterval; running: root.automaticEnabled || !root.automatic.ready; repeat: true
        onTriggered: { if (!root.automatic.ready) root.refresh(); else root.tick() }
    }
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
                const policy = data.automatic
                if (!policy || typeof policy.ready !== "boolean" || !policy.settings || typeof policy.settings.enabled !== "boolean"
                    || !policy.source || typeof policy.source.available !== "boolean" || typeof policy.message !== "string"
                    || (policy.source.available && (typeof policy.source.onBattery !== "boolean" || typeof policy.source.percentage !== "number"
                        || !Number.isFinite(policy.source.percentage) || policy.source.percentage < 0 || policy.source.percentage > 100))
                    || (policy.ready && (policy.settings.version !== 1 || ["ac", "battery", "low"].some(key => !["power-saver", "balanced", "performance"].includes(policy.settings[key]))
                        || !Number.isInteger(policy.settings.threshold) || policy.settings.threshold < 5 || policy.settings.threshold > 50)))
                    throw new Error("Invalid automatic power response.")
                if (!root.ready) root.error = ""
                root.automatic = policy
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
            if (root.tickAfterRead) {
                root.tickAfterRead = false
                Qt.callLater(() => root.tick())
            }
        }
    }
    property Process action: Process {
        stdinEnabled: true
        onStarted: {
            if (root.actionKind === "configure") write(root.pendingConfig + "\n")
            stdinEnabled = false
        }
        stderr: StdioCollector { id: writeError }
        onExited: (code, exitStatus) => {
            const failed = code !== 0 || exitStatus !== 0
            const message = failed ? writeError.text.trim() || "Could not change the power profile." : ""
            if (root.actionKind === "automatic") root.automaticRunError = message
            else if (root.actionKind === "configure") root.automaticSaveError = message
            else root.error = message
            root.tickAfterRead = root.actionKind === "configure" && !failed
            root.actionKind = ""; root.pendingConfig = ""
            stdinEnabled = true
            root.verifying = true
            // Always read back, including after failure or after the last view closes.
            root.status.running = true
        }
    }
}
