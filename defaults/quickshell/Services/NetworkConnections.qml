import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property string helper: Quickshell.env("HOME") + "/.local/share/blankweave/shell/network-connections.py"
    property bool settingsActive: false
    property var owners: []
    readonly property bool active: settingsActive || owners.length > 0
    property bool ready: false
    property var devices: []
    property string error: ""
    property string notice: ""
    property string pending: ""
    readonly property bool busy: status.running || action.running || pending !== ""
    readonly property var ethernet: devices.filter(row => row.kind === "ethernet")
    readonly property var connected: devices.filter(row => row.connected && row.managed)
    readonly property var providers: ["Automatic", "Cloudflare", "Google", "Quad9", "OpenDNS", "Custom"]

    function setActive(owner, value) {
        const next = owners.filter(item => item !== owner)
        if (value) next.push(owner)
        owners = next
    }
    function refresh(clearError = false) {
        if (busy) return
        if (clearError) { error = ""; notice = "" }
        status.running = true
    }
    function matches(a, b) {
        return a && b && ["owner", "path", "interface", "uuid", "activePath"].every(key => a[key] === b[key])
    }
    function execute(row, options) {
        if (!ready || busy) return
        if (!devices.some(current => matches(current, row))) {
            error = "The connection changed. Refresh and try again."
            return
        }
        error = ""; notice = ""
        pending = JSON.stringify(Object.assign({}, options, {owner: row.owner, path: row.path,
            interface: row.interface, uuid: row.uuid, activePath: row.activePath}))
        action.running = true
    }
    function connectDevice(row, profile) {
        if (row.kind === "ethernet" && row.managed && row.carrier && !row.connected && row.activePath === "/")
            execute(row, {action: "connect", profile: profile})
    }
    function disconnectDevice(row) { if (row.kind === "ethernet" && row.connected) execute(row, {action: "disconnect"}) }
    function setDns(row, provider, ipv4 = "", ipv6 = "") {
        if (row.connected && row.managed && providers.includes(provider))
            execute(row, {action: "dns", provider: provider, ipv4: ipv4, ipv6: ipv6})
    }
    onActiveChanged: if (active) refresh(true)
    property Timer poll: Timer { interval: 5000; running: root.active; repeat: true; onTriggered: root.refresh() }
    property Process status: Process {
        command: ["python3", root.helper, "status"]
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: readError }
        onExited: (code, exitStatus) => {
            try {
                if (code !== 0 || exitStatus !== 0) throw new Error(readError.text.trim() || "NetworkManager is unavailable.")
                const data = JSON.parse(output.text)
                if (!Array.isArray(data.devices) || data.devices.some(row => !row ||
                    ["path", "owner", "interface", "uuid", "activePath", "name", "kind", "provider"].some(key => typeof row[key] !== "string") ||
                    ["connected", "managed", "carrier", "default"].some(key => typeof row[key] !== "boolean") ||
                    typeof row.state !== "number" || typeof row.speed !== "number" || !Array.isArray(row.profiles) ||
                    row.profiles.some(profile => typeof profile.uuid !== "string" || typeof profile.name !== "string") ||
                    [4, 6].some(v => !row["ipv" + v] || !Array.isArray(row["ipv" + v].addresses) ||
                        !Array.isArray(row["ipv" + v].dns) || typeof row["ipv" + v].gateway !== "string" ||
                        !row.dns || !row.dns[String(v)] || !Array.isArray(row.dns[String(v)].servers) ||
                        typeof row.dns[String(v)].enabled !== "boolean" || typeof row.dns[String(v)].automatic !== "boolean")))
                    throw new Error("Invalid network status response.")
                root.devices = data.devices
                root.ready = true
            } catch (error) { root.ready = false; root.devices = []; root.error = String(error) }
        }
    }
    property Process action: Process {
        command: ["python3", root.helper, "apply"]
        stdinEnabled: true
        onStarted: { write(root.pending + "\n"); stdinEnabled = false }
        stderr: StdioCollector { id: writeError }
        onExited: (code, exitStatus) => {
            if (code !== 0 || exitStatus !== 0) root.error = writeError.text.trim() || "Could not change the connection."
            else root.notice = "Network settings updated."
            root.pending = ""
            stdinEnabled = true
            Qt.callLater(() => root.refresh())
        }
    }
}
