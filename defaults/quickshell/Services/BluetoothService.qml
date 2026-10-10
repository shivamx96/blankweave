import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire

QtObject {
    id: root
    property var provider: Bluetooth
    property var audioProvider: Pipewire
    property string helper: Quickshell.env("HOME") + "/.local/share/blankweave/shell/bluetooth-action.py"
    property string powerHelper: Quickshell.env("HOME") + "/.local/share/blankweave/shell/bluetooth-power.sh"
    readonly property var adapter: provider.defaultAdapter
    readonly property var rawDevices: provider.devices ? provider.devices.values : []
    readonly property bool enabled: adapter !== null && adapter.enabled
    property bool externalBusy: false
    readonly property bool busy: externalBusy || localBusy
    readonly property bool localBusy: action.running || power.running || actionKey !== ""
    property string actionKey: ""
    property string actionKind: ""
    property var actionOwner: null
    property var prompt: null
    property string error: ""
    property bool resultReceived: false
    property bool resultSuccess: false
    property string actionAddress: ""
    property string actionName: ""
    property bool cancelled: false
    property var scanOwners: []
    property var discoveryAdapter: null
    property var stoppingAdapters: []
    property int discoveryAttempts: 0
    property int discoveryInterval: 700
    property int actionTimeoutMs: 110000
    property var pendingAudioDevice: null
    property int audioAttempts: 0
    property bool settingsActive: false
    property bool settingsScanning: true
    onSettingsActiveChanged: {
        if (settingsActive) settingsScanning = true
        setScanRequest(root, settingsActive && settingsScanning)
    }
    onSettingsScanningChanged: setScanRequest(root, settingsActive && settingsScanning)
    function deviceLabel(device) {
        return String(device && (device.deviceName || device.name) || "").trim()
    }

    function humanName(device) {
        const label = root.deviceLabel(device)
        if (!label || /^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(label))
            return false
        return !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(label)
            && !/^[0-9a-f]{32}$/i.test(label)
            && !/^0x[0-9a-f]{4,32}$/i.test(label)
    }

    function deviceSnapshot(device) {
        return {
            "address": String(device.address || ""),
            "key": String(device.dbusPath || ""),
            "blocked": Boolean(device.blocked),
            "name": root.deviceLabel(device) || String(device.address || "Bluetooth device"),
            "icon": String(device.icon || ""),
            "connected": Boolean(device.connected),
            "paired": Boolean(device.paired),
            "bonded": Boolean(device.bonded),
            "trusted": Boolean(device.trusted),
            "pairing": Boolean(device.pairing),
            "state": Number(device.state),
            "batteryAvailable": Boolean(device.batteryAvailable),
            "battery": Number(device.battery || 0)
        }
    }

    readonly property var deviceGroups: {
        const connected = []
        const known = []
        const discovered = []

        for (let index = 0; index < rawDevices.length; index++) {
            const device = rawDevices[index]
            if (!device || device.adapter !== adapter || (!root.humanName(device) && !device.paired && !device.bonded && !device.trusted))
                continue

            const row = root.deviceSnapshot(device)
            if (row.connected)
                connected.push(row)
            else if (row.paired || row.bonded || row.trusted)
                known.push(row)
            else
                discovered.push(row)
        }

        const byName = (left, right) => left.name.localeCompare(right.name)
        connected.sort(byName)
        known.sort(byName)
        discovered.sort(byName)
        return { "connected": connected, "known": known, "discovered": discovered }
    }

    readonly property var connectedDevices: deviceGroups.connected
    readonly property var deviceRows: {
        const rows = []
        for (let index = 0; index < deviceGroups.connected.length; index++)
            rows.push({ "section": "CONNECTED", "device": deviceGroups.connected[index] })
        for (let index = 0; index < deviceGroups.known.length; index++)
            rows.push({ "section": "PAIRED", "device": deviceGroups.known[index] })
        if (adapter && adapter.discovering) {
            for (let index = 0; index < deviceGroups.discovered.length; index++)
                rows.push({ "section": "AVAILABLE", "device": deviceGroups.discovered[index] })
        }
        return rows
    }

    function liveDevice(key) { return rawDevices.find(device => device && device.adapter === adapter && String(device.dbusPath) === key) || null }
    function pendingAction(address) {
        if (address !== actionAddress) return ""
        return ({pair:"pairing",connect:"connecting",disconnect:"disconnecting",forget:"forgetting"})[actionKind] || ""
    }
    function connectDevice(key, owner) {
        const device = liveDevice(key)
        if (device && !device.connected) runAction(device.paired || device.bonded ? "connect" : "pair", key, owner)
    }
    function runAction(kind, key, owner) {
        const device = liveDevice(key)
        if (busy || !enabled || !device || device.pairing) return
        if (!["pair", "connect", "disconnect", "forget"].includes(kind)) return
        if (device.blocked && ["pair", "connect"].includes(kind)) return
        error = ""
        actionKey = key
        actionAddress = String(device.address)
        actionName = deviceLabel(device) || actionAddress
        actionKind = kind
        actionOwner = owner
        prompt = null
        resultReceived = false
        resultSuccess = false
        cancelled = false
        action.command = ["python3", helper, kind, key]
        action.running = true
        actionTimeout.restart()
    }
    function respond(value) {
        if (prompt && action.running) action.write(JSON.stringify({id: prompt.id, value: value}) + "\n")
    }
    function cancelPairing() {
        if (actionKind !== "pair" || !action.running || cancelled) return
        cancelled = true
        prompt = null
        action.write('{"cancel":true}\n')
    }
    function cancelForOwner(owner) { if (actionOwner === owner) cancelPairing() }
    function consume(payload) {
        try {
            const data = JSON.parse(payload)
            if (data.kind === "prompt") {
                if (!cancelled) prompt = data.prompt
            } else if (data.kind === "result") {
                resultReceived = true
                resultSuccess = data.success === true
                if (!resultSuccess) error = String(data.message || "Bluetooth request failed.")
                prompt = null
            }
        } catch (_) { error = "Invalid Bluetooth response." }
    }
    function togglePower() {
        if (!adapter || busy) return
        error = ""
        power.command = ["bash", powerHelper, enabled ? "off" : "on"]
        power.running = true
    }
    property Process action: Process {
        stdinEnabled: true
        onStarted: if (root.cancelled) write('{"cancel":true}\n')
        stdout: SplitParser { onRead: data => root.consume(data) }
        stderr: StdioCollector { id: actionError }
        onExited: (code, status) => {
            actionTimeout.stop()
            if (code !== 0 || status !== 0 || !root.resultReceived || !root.resultSuccess) {
                if (!root.error) root.error = actionError.text.trim() || "Bluetooth request failed. Try again."
            } else if (["connect", "pair"].includes(root.actionKind) && !root.cancelled) {
                root.pendingAudioDevice = {key:root.actionKey,address:root.actionAddress}
                root.audioAttempts = 0
                audioTimer.restart()
            }
            root.actionKey = ""
            root.actionKind = ""
            root.actionAddress = ""
            root.actionName = ""
            root.actionOwner = null
            root.prompt = null
        }
    }
    property Timer actionTimeout: Timer {
        interval: root.actionTimeoutMs
        onTriggered: {
            root.error = "Bluetooth request timed out. Try again."
            action.signal(15)
        }
    }
    property Process power: Process {
        stderr: StdioCollector { id: powerError }
        onExited: (code, status) => {
            if (code !== 0 || status !== 0) root.error = powerError.text.trim() || "Could not change Bluetooth power. Check the hardware switch and try again."
        }
    }

    function setScanRequest(owner, active) {
        const owners = scanOwners.filter(item => item !== owner)
        if (active) owners.push(owner)
        scanOwners = owners
        updateDiscovery()
    }
    function updateDiscovery() {
        const next = enabled && !externalBusy && scanOwners.length ? adapter : null
        if (next === discoveryAdapter) return
        if (discoveryAdapter) {
            discoveryAdapter.discovering = false
            stoppingAdapters = stoppingAdapters.concat([{adapter:discoveryAdapter,remaining:3}])
        }
        discoveryAdapter = next
        discoveryAttempts = 0
        if (next) {
            stoppingAdapters = stoppingAdapters.filter(row => row.adapter !== next)
            next.discovering = true
        }
    }
    onExternalBusyChanged: updateDiscovery()
    onAdapterChanged: { updateDiscovery(); if (actionKind === "pair" && !liveDevice(actionKey)) cancelPairing() }
    onEnabledChanged: { updateDiscovery(); if (!enabled) cancelPairing() }
    property Timer discoveryTimer: Timer {
        interval: root.discoveryInterval
        running: root.discoveryAdapter !== null || root.stoppingAdapters.length > 0
        repeat: true
        onTriggered: {
            if (root.discoveryAdapter && !root.discoveryAdapter.discovering && root.discoveryAttempts++ < 3)
                root.discoveryAdapter.discovering = true
            const remaining = []
            for (const row of root.stoppingAdapters) {
                if (row.adapter && row.adapter.discovering) row.adapter.discovering = false
                if (row.adapter && row.remaining > 1) remaining.push({adapter:row.adapter,remaining:row.remaining - 1})
            }
            root.stoppingAdapters = remaining
        }
    }
    Component.onDestruction: {
        if (discoveryAdapter) discoveryAdapter.discovering = false
        for (const row of stoppingAdapters) if (row.adapter) row.adapter.discovering = false
        cancelPairing()
    }

    function switchAudioOutput() {
        if (!pendingAudioDevice) return
        const device = liveDevice(pendingAudioDevice.key)
        if (!device || !device.connected) { pendingAudioDevice = null; return }
        const address = pendingAudioDevice.address.toLowerCase().replace(/[^0-9a-f]/g, "")
        const nodes = audioProvider && audioProvider.nodes ? audioProvider.nodes.values : []
        const sink = nodes.find(node => {
            if (!node || !node.isSink || node.isStream) return false
            const properties = node.ready && node.properties ? node.properties : ({})
            const identifiers = [node.name, properties["api.bluez5.address"], properties["bluez5.address"]]
            return identifiers.some(value => String(value || "").toLowerCase().replace(/[^0-9a-f]/g, "").includes(address))
        })
        if (sink) {
            audioProvider.preferredDefaultAudioSink = sink
            persistAudio.command = ["bash", Quickshell.env("HOME") + "/.local/share/blankweave/shell/audio-output-default.sh", String(sink.id), String(sink.name)]
            persistAudio.running = true
            pendingAudioDevice = null
        } else if (++audioAttempts < 8) audioTimer.restart()
        else pendingAudioDevice = null
    }
    property PwObjectTracker audioTracker: PwObjectTracker { objects: root.audioProvider && root.audioProvider.nodes ? root.audioProvider.nodes.values : [] }
    property Timer audioTimer: Timer { interval: 500; onTriggered: root.switchAudioOutput() }
    property Process persistAudio: Process {
        onExited: (code, status) => { if (code !== 0 || status !== 0) root.error = "Bluetooth connected, but the preferred audio output could not be saved." }
    }
}
