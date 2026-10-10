import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property string helper: Quickshell.env("HOME") + "/.local/share/blankweave/shell/wireless-controls.py"
    property var wifi: null
    property var bluetooth: null
    property var connections: null
    property bool active: false
    property var airplane: null
    property var network: null
    property string radioError: ""
    property string networkError: ""
    property string error: ""
    property string notice: ""
    property string pending: ""
    property bool applying: false
    readonly property bool busy: applying || status.running
    readonly property bool otherBusy: (wifi && wifi.localBusy) || (bluetooth && bluetooth.localBusy) || (connections && connections.localBusy)
    readonly property var devices: network ? network.devices : []
    readonly property var hotspots: devices.filter(row => row.hotspot)
    readonly property bool airplaneRequested: airplane !== null && airplane.requested
    readonly property bool radiosBlocked: airplane !== null && airplane.blocked
    property Binding connectionsLock: Binding { target: root.connections; property: "externalBusy"; value: root.applying; when: root.connections !== null }
    property Binding wifiLock: Binding { target: root.wifi; property: "externalBusy"; value: root.applying; when: root.wifi !== null }
    property Binding bluetoothLock: Binding { target: root.bluetooth; property: "externalBusy"; value: root.applying; when: root.bluetooth !== null }

    function matches(a, b) {
        return a && b && ["owner", "path", "interface", "uuid", "activePath"].every(key => a[key] === b[key])
    }
    function refresh(clearError = false) {
        if (busy) return
        if (clearError) { error = ""; notice = "" }
        status.running = true
    }
    function execute(request) {
        if (busy || otherBusy) return
        error = ""; notice = ""
        pending = JSON.stringify(request)
        applying = true
        action.running = true
    }
    function setAirplane(value) {
        if (airplane && airplane.radios.length) execute({action: "airplane", enabled: value})
    }
    function hotspotAction(row, options) {
        if (!devices.some(current => matches(current, row))) { error = "The Wi-Fi connection changed. Refresh and try again."; return }
        execute(Object.assign({}, options, {owner: row.owner, path: row.path, interface: row.interface,
            uuid: row.uuid, activePath: row.activePath}))
    }
    function start(row, ssid, password, replace) {
        if (!network || !network.sharingAvailable || !network.wifiEnabled || !network.hardwareEnabled || airplaneRequested || !row.apCapable || row.hotspot) return
        hotspotAction(row, {action: "start", ssid: ssid, password: password, replace: replace})
    }
    function stop(row) { if (row.hotspot && row.owned) hotspotAction(row, {action: "stop"}) }
    onActiveChanged: if (active) refresh(true)
    property Timer poll: Timer { interval: 5000; running: root.active; repeat: true; onTriggered: root.refresh() }
    property Process status: Process {
        command: ["python3", root.helper, "status"]
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: readError }
        onExited: (code, exitStatus) => {
            try {
                if (code !== 0 || exitStatus !== 0) throw new Error(readError.text.trim() || "Wireless controls are unavailable.")
                const data = JSON.parse(output.text)
                if (typeof data.radioError !== "string" || typeof data.networkError !== "string"
                    || (data.airplane !== null && (typeof data.airplane.requested !== "boolean" || typeof data.airplane.blocked !== "boolean"
                        || !Array.isArray(data.airplane.radios) || data.airplane.radios.some(row => typeof row.name !== "string" || typeof row.type !== "string" || typeof row.soft !== "boolean" || typeof row.hard !== "boolean")))
                    || (data.network !== null && (typeof data.network.wifiEnabled !== "boolean" || typeof data.network.hardwareEnabled !== "boolean"
                        || typeof data.network.sharingAvailable !== "boolean" || !Array.isArray(data.network.devices)
                        || data.network.devices.some(row => ["owner", "path", "interface", "uuid", "activePath", "name", "ssid"].some(key => typeof row[key] !== "string")
                            || ["hotspot", "owned", "apCapable", "connected", "managed"].some(key => typeof row[key] !== "boolean") || typeof row.state !== "number"))))
                    throw new Error("Invalid wireless status response.")
                root.airplane = data.airplane; root.network = data.network
                root.radioError = data.radioError; root.networkError = data.networkError
            } catch (error) { root.airplane = null; root.network = null; root.error = String(error) }
        }
    }
    property Process action: Process {
        command: ["python3", root.helper, "apply"]
        stdinEnabled: true
        onStarted: { write(root.pending + "\n"); root.pending = ""; stdinEnabled = false }
        stderr: StdioCollector { id: writeError }
        onExited: (code, exitStatus) => {
            root.pending = ""; root.applying = false; stdinEnabled = true
            if (code !== 0 || exitStatus !== 0) root.error = writeError.text.trim() || "Could not change wireless settings."
            else root.notice = "Wireless settings updated."
            Qt.callLater(() => { root.refresh(); if (root.connections) root.connections.refresh() })
        }
    }
}
