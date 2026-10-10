import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

QtObject {
    id: root
    property var provider: Networking
    readonly property var networkDevices: provider.devices ? provider.devices.values : []
    readonly property var wifiDevice: findDevice(DeviceType.Wifi)
    readonly property var wiredDevice: findDevice(DeviceType.Wired)
    readonly property var wifiNetworkObjects: wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
    readonly property var connectedWifiNetwork: wifiNetworkObjects.find(network => network && network.connected) || null
    readonly property bool available: provider.backend === NetworkBackendType.NetworkManager
    readonly property bool enabled: available && provider.wifiEnabled
    readonly property bool hardwareEnabled: available && provider.wifiHardwareEnabled
    readonly property bool managed: wifiDevice !== null && wifiDevice.nmManaged
    readonly property bool hosting: wifiDevice !== null && wifiDevice.mode === WifiDeviceMode.AccessPoint
    readonly property bool usable: available && enabled && hardwareEnabled && managed && !hosting && !externalBusy
    property bool externalBusy: false
    readonly property bool busy: externalBusy || localBusy
    readonly property bool localBusy: actionKind !== "" || enterpriseConnect.running || profileAction.running
    property bool profilesActive: false
    property string profilesHelper: Quickshell.env("HOME") + "/.local/share/blankweave/shell/wifi-profiles.py"
    property var profiles: []
    property bool profilesReady: false
    property string profilesError: ""
    readonly property bool profilesBusy: profileStatus.running || profileAction.running
    property var scanOwners: []
    property var scannerDevice: null
    property string actionKind: ""
    property string actionSsid: ""
    property string actionKey: ""
    property string failureSsid: ""
    property string failureReason: ""
    property int actionTimeoutMs: 30000
    property string enterpriseSecret: ""
    signal credentialsRequired(string key)
    signal actionSucceeded()

    function findDevice(type) {
        const devices = networkDevices.filter(device => device && device.type === type)
        return devices.find(device => device.connected) || devices.find(device => device.nmManaged) || devices[0] || null
    }
    function keyForNetwork(network) {
        return JSON.stringify([String(wifiDevice.name), String(network.name), Number(network.security)])
    }
    function keyForSsid(ssid) {
        const network = networkForSsid(ssid)
        return network ? keyForNetwork(network) : ""
    }
    function ssidForKey(key) { try { return JSON.parse(key)[1] } catch (_) { return "" } }
    function networkForSsid(ssid) { return wifiNetworkObjects.find(network => network && String(network.name) === ssid) || null }
    function networkForKey(key) { return wifiNetworkObjects.find(network => network && keyForNetwork(network) === key) || null }
    function requiresCredentials(security) { return security !== WifiSecurityType.Open && security !== WifiSecurityType.Owe }
    function isEnterprise(security) { return security === WifiSecurityType.Wpa2Eap || security === WifiSecurityType.WpaEap }
    function supportsPassword(security) { return [WifiSecurityType.WpaPsk, WifiSecurityType.Wpa2Psk, WifiSecurityType.Sae].includes(security) }
    readonly property var wifiRows: {
        const rows = wifiNetworkObjects.filter(network => network && String(network.name)).map(network => ({
            key: keyForNetwork(network), ssid: String(network.name), connected: Boolean(network.connected),
            known: Boolean(network.known), stateChanging: Boolean(network.stateChanging),
            signal: Math.round(Number(network.signalStrength || 0) * 100), security: Number(network.security)
        }))
        rows.sort((a, b) => Number(b.connected) - Number(a.connected) || Number(b.known) - Number(a.known)
            || b.signal - a.signal || a.ssid.localeCompare(b.ssid))
        return rows
    }
    function setScanRequest(owner, active) {
        const owners = scanOwners.filter(item => item !== owner)
        if (active) owners.push(owner)
        scanOwners = owners
        updateScanner()
    }
    function updateScanner() {
        const device = usable && scanOwners.length ? wifiDevice : null
        if (scannerDevice && scannerDevice !== device) scannerDevice.scannerEnabled = false
        scannerDevice = device
        if (device) device.scannerEnabled = true
    }
    onUsableChanged: updateScanner()
    onWifiDeviceChanged: { updateScanner(); checkActionCompletion() }
    Component.onDestruction: if (scannerDevice) scannerDevice.scannerEnabled = false

    function startAction(kind, key) {
        if (busy) return false
        const network = networkForKey(key)
        if (!usable || !network || network.stateChanging) {
            failureReason = "That network is unavailable. Refresh the list and try again."
            return false
        }
        failureReason = ""
        failureSsid = ""
        actionKey = key
        actionSsid = String(network.name)
        actionKind = kind
        actionTimeout.restart()
        return true
    }
    function clearAction() {
        actionTimeout.stop()
        actionKind = ""
        actionKey = ""
        actionSsid = ""
    }
    function failAction(message) {
        failureSsid = actionSsid
        failureReason = message
        clearAction()
    }
    function setEnabled(value) {
        if (busy || !available || !wifiDevice || !hardwareEnabled || typeof value !== "boolean") return
        if (enabled === value) return
        failureReason = ""
        actionKind = value ? "enable" : "disable"
        actionTimeout.restart()
        provider.wifiEnabled = value
    }
    function connectNetwork(key, password = "", identity = "") {
        const network = networkForKey(key)
        if (!network || network.connected || !startAction("connect", key)) return
        if (password && isEnterprise(Number(network.security))) {
            if (!identity) { failAction("Identity required."); return }
            enterpriseSecret = password
            enterpriseConnect.command = [Quickshell.env("HOME") + "/.local/share/blankweave/shell/wifi-enterprise-connect.sh", String(network.name), identity]
            enterpriseConnect.running = true
        } else if (password && supportsPassword(Number(network.security))) {
            network.connectWithPsk(password)
        } else if (network.known || !requiresCredentials(Number(network.security))) {
            network.connect()
        } else {
            failAction(supportsPassword(Number(network.security)) ? "Enter the Wi-Fi password." : "Set up this network’s security in a NetworkManager connection editor first.")
            if (supportsPassword(Number(network.security))) credentialsRequired(key)
        }
    }
    function disconnectNetwork(key) {
        const network = networkForKey(key)
        if (network && network.connected && startAction("disconnect", key)) network.disconnect()
    }
    function forgetNetwork(key) {
        const network = networkForKey(key)
        if (network && network.known && !network.connected && startAction("forget", key)) network.forget()
    }
    function checkActionCompletion() {
        if (!actionKind) return
        const network = networkForKey(actionKey)
        if ((actionKind === "enable" && enabled) || (actionKind === "disable" && !enabled)
            || (actionKind === "connect" && network && network.connected)
            || (actionKind === "disconnect" && network && !network.connected && !network.stateChanging)
            || (actionKind === "forget" && (!network || !network.known))) {
            clearAction()
            actionSucceeded()
        } else if (actionKey && !network) failAction("The network is no longer available.")
    }
    onWifiRowsChanged: checkActionCompletion()
    onEnabledChanged: checkActionCompletion()
    property Connections pendingNetwork: Connections {
        target: root.networkForKey(root.actionKey)
        function onConnectionFailed(reason) {
            if (root.actionKind !== "connect") return
            const key = root.actionKey
            root.failAction(reason === ConnectionFailReason.NoSecrets ? "Passphrase required."
                : reason === ConnectionFailReason.WifiAuthTimeout ? "Wi-Fi authentication failed. Check the password."
                : reason === ConnectionFailReason.WifiNetworkLost ? "Network lost." : "Connection failed.")
            if (reason === ConnectionFailReason.NoSecrets || reason === ConnectionFailReason.WifiAuthTimeout)
                root.credentialsRequired(key)
        }
    }
    property Timer actionTimeout: Timer {
        interval: root.actionTimeoutMs
        onTriggered: root.failAction("Wi-Fi request timed out. Check the connection and try again.")
    }
    property Process enterpriseConnect: Process {
        stdinEnabled: true
        onStarted: { write(root.enterpriseSecret + "\n"); root.enterpriseSecret = "" }
        onExited: (code, status) => {
            root.enterpriseSecret = ""
            if (code !== 0 || status !== 0) root.failAction("Enterprise login failed.")
        }
    }

    function refreshProfiles() {
        if (!profilesBusy) profileStatus.running = true
    }
    function forgetProfile(uuid) {
        if (busy || profilesBusy || !profilesReady) return
        const profile = profiles.find(row => row.uuid === uuid)
        if (!profile || profile.active) return
        profilesError = ""
        profileAction.command = ["python3", profilesHelper, "forget", uuid]
        profileAction.running = true
    }
    onProfilesActiveChanged: if (profilesActive) refreshProfiles()
    property Timer profilePoll: Timer { interval: 15000; running: root.profilesActive; repeat: true; onTriggered: root.refreshProfiles() }
    property Process profileStatus: Process {
        command: ["python3", root.profilesHelper, "status"]
        stdout: StdioCollector { id: profileOutput }
        stderr: StdioCollector { id: profileReadError }
        onExited: (code, status) => {
            try {
                if (code !== 0 || status !== 0) throw new Error(profileReadError.text.trim() || "Saved networks are unavailable.")
                const rows = JSON.parse(profileOutput.text)
                if (!Array.isArray(rows) || rows.some(row => !row || typeof row.uuid !== "string" || typeof row.name !== "string"
                    || typeof row.ssid !== "string" || typeof row.active !== "boolean")) throw new Error("Invalid saved network response.")
                root.profiles = rows
                root.profilesReady = true
            } catch (error) { root.profilesReady = false; root.profilesError = String(error) }
        }
    }
    property Process profileAction: Process {
        stderr: StdioCollector { id: profileWriteError }
        onExited: (code, status) => {
            if (code !== 0 || status !== 0) root.profilesError = profileWriteError.text.trim() || "Could not forget the saved network."
            Qt.callLater(() => root.refreshProfiles())
        }
    }
}
