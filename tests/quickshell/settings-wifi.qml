import QtQuick
import Quickshell
import Quickshell.Networking
import "Services"
import "Settings"
import "Modules"

ShellRoot {
    id: test
    property var palette: ({surfaceRaised:"#182334",surfaceHover:"#263955",surfacePressed:"#304563",
        text:"#e7edf7",textMuted:"#a1aec4",accentBright:"#67a6ff",accentSurface:"#1e3556",
        outline:"#33476a",divider:"#23314a",critical:"#ff8080",accent:"#67a6ff",fontFamily:"sans-serif",
        smallTextSize:12,textSize:13,widgetRadius:4})
    QtObject {
        id: network
        property string name: "Test Wi-Fi"
        property bool connected: false
        property bool known: true
        property bool stateChanging: false
        property real signalStrength: .8
        property int security: WifiSecurityType.Wpa2Psk
        property string lastAction: ""
        property string psk: ""
        signal connectionFailed(int reason)
        function connect() { lastAction = "connect" }
        function connectWithPsk(password) { lastAction = "password"; psk = password }
        function disconnect() { lastAction = "disconnect" }
        function forget() { lastAction = "forget" }
    }
    QtObject {
        id: device
        property string name: "wlan-test"
        property int type: DeviceType.Wifi
        property bool connected: false
        property bool nmManaged: true
        property bool scannerEnabled: false
        property QtObject networks: QtObject { property var values: [] }
    }
    QtObject {
        id: provider
        property int backend: NetworkBackendType.NetworkManager
        property bool wifiEnabled: true
        property bool wifiHardwareEnabled: true
        property QtObject devices: QtObject { property var values: [] }
    }
    NetworkWifi { id: wifi; provider: provider; profilesHelper: Qt.resolvedUrl("profiles.py").toString().replace("file://", "") }
    FloatingWindow { visible: true; implicitWidth: 680; implicitHeight: 1100
        SettingsWifi { id: controls; theme: test.palette; backend: wifi; width: 620 }
    }

    Theme { id: barTheme }
    FloatingWindow {
        id: barStub
        property bool atBottom: false
        function setVisibilityHold(owner, held) {}
        function hideTooltip(owner) {}
        function showTooltip(owner, text) {}
        NetworkWidget { theme: barTheme; bar: barStub; wifi: wifi; iconOnly: true }
    }
    property int step: 0
    readonly property var cases: [test_scan_ownership_and_hotplug, test_connection_readback_and_external_changes,
        test_stale_identity_and_snapshot, test_password_is_cleared_and_used_only_for_selected_network,
        test_failure_timeout_and_retry, test_unavailable_hardware_and_radio_readback,
        test_saved_forget_confirmation_and_active_guard]
    function verify(value) { if (!value) throw new Error("Assertion failed at step " + step) }
    function compare(actual, expected) { if (actual !== expected) throw new Error("Step " + step + ": expected " + expected + ", got " + actual) }
    function tryCompare(object, key, expected) { compare(object[key], expected) }
    function findChild(parent, name) {
        if (parent.objectName === name) return parent
        for (const child of parent.children || []) {
            const found = findChild(child, name)
            if (found) return found
        }
        return null
    }
    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            try {
                if (test.step < test.cases.length) { test.init(); test.cases[test.step](); test.cleanup() }
                else if (test.step === test.cases.length) {
                    test.init(); wifi.actionTimeoutMs = 20; wifi.connectNetwork(wifi.keyForSsid(network.name))
                } else if (test.step === test.cases.length + 1) {
                    test.verify(!wifi.busy); test.verify(wifi.failureReason.includes("timed out"))
                    wifi.refreshProfiles()
                } else if (test.step === test.cases.length + 2) {
                    if (wifi.profilesBusy) return
                    test.verify(wifi.profilesReady); test.compare(wifi.profiles.length, 2)
                    wifi.forgetProfile("profile-test")
                } else if (test.step === test.cases.length + 3) {
                    if (wifi.profilesBusy) return
                    test.compare(wifi.profiles.length, 1)
                    wifi.forgetProfile("profile-fail")
                } else {
                    if (wifi.profilesBusy) return
                    test.compare(wifi.profiles.length, 1)
                    test.verify(wifi.profilesError.includes("Permission denied"))
                    console.log("SETTINGS_WIFI_PASSED"); Qt.quit()
                }
                test.step++
            } catch (error) { console.error(String(error), error.stack); Qt.quit() }
        }
    }
    function init() {
        wifi.clearAction()
        wifi.failureReason = ""
        wifi.failureSsid = ""
        wifi.actionTimeoutMs = 30000
        wifi.setScanRequest("settings", false)
        wifi.setScanRequest("bar", false)
        controls.clearPassword()
        provider.backend = NetworkBackendType.NetworkManager
        provider.wifiHardwareEnabled = true
        provider.wifiEnabled = true
        device.nmManaged = true
        device.name = "wlan-test"
        network.name = "Test Wi-Fi"
        network.connected = false
        network.known = true
        network.stateChanging = false
        network.security = WifiSecurityType.Wpa2Psk
        network.lastAction = ""
        network.psk = ""
        provider.devices.values = [device]
        device.networks.values = [network]
        wifi.profiles = [{uuid:"saved-test",name:"Not nearby",ssid:"Not nearby",active:false}]
        wifi.profilesReady = true
    }
    function cleanup() { wifi.clearAction(); wifi.setScanRequest("settings", false); wifi.setScanRequest("bar", false) }
    function test_scan_ownership_and_hotplug() {
        wifi.setScanRequest("settings", true)
        verify(device.scannerEnabled)
        wifi.setScanRequest("bar", true)
        wifi.setScanRequest("settings", false)
        verify(device.scannerEnabled)
        provider.wifiHardwareEnabled = false
        verify(!device.scannerEnabled)
        provider.wifiHardwareEnabled = true
        verify(device.scannerEnabled)
        provider.devices.values = []
        verify(!device.scannerEnabled)
        provider.devices.values = [device]
        verify(device.scannerEnabled)
        wifi.setScanRequest("bar", false)
        verify(!device.scannerEnabled)
    }
    function test_connection_readback_and_external_changes() {
        const key = wifi.keyForSsid(network.name)
        wifi.connectNetwork(key)
        compare(network.lastAction, "connect")
        verify(wifi.busy)
        verify(!wifi.wifiRows[0].connected)
        network.connected = true
        tryCompare(wifi, "busy", false)
        compare(findChild(controls, "wifiConnect:" + key).text, "Disconnect")
        wifi.disconnectNetwork(key)
        compare(network.lastAction, "disconnect")
        network.connected = false
        tryCompare(wifi, "busy", false)
    }
    function test_stale_identity_and_snapshot() {
        const row = wifi.wifiRows[0]
        network.security = WifiSecurityType.Open
        wifi.connectNetwork(row.key)
        compare(network.lastAction, "")
        compare(row.security, WifiSecurityType.Wpa2Psk)
        const key = wifi.keyForSsid(network.name)
        device.name = "another-adapter"
        wifi.connectNetwork(key)
        compare(network.lastAction, "")
    }
    function test_password_is_cleared_and_used_only_for_selected_network() {
        network.known = false
        controls.requestConnect(wifi.wifiRows[0])
        const password = findChild(controls, "wifiPassword")
        password.text = "test secret"
        controls.submitPassword()
        compare(network.lastAction, "password")
        compare(network.psk, "test secret")
        compare(password.text, "")
        compare(controls.passwordKey, "")
        wifi.clearAction()
        controls.requestConnect(wifi.wifiRows[0])
        password.text = "unused secret"
        device.networks.values = []
        compare(password.text, "")
        compare(controls.passwordKey, "")
    }
    function test_failure_timeout_and_retry() {
        const key = wifi.keyForSsid(network.name)
        wifi.connectNetwork(key)
        network.connectionFailed(ConnectionFailReason.WifiAuthTimeout)
        verify(!wifi.busy)
        verify(wifi.failureReason.includes("authentication"))

    }
    function test_unavailable_hardware_and_radio_readback() {
        wifi.setEnabled(false)
        compare(provider.wifiEnabled, false)
        tryCompare(wifi, "busy", false)
        provider.wifiHardwareEnabled = false
        wifi.setEnabled(true)
        compare(provider.wifiEnabled, false)
        verify(!findChild(controls, "wifiPower").enabled)
        provider.devices.values = []
        verify(findChild(controls, "wifiStatus").text.includes("No Wi-Fi adapter"))
        provider.backend = NetworkBackendType.None
        verify(findChild(controls, "wifiStatus").text.includes("unavailable"))
    }
    function test_saved_forget_confirmation_and_active_guard() {
        const button = findChild(controls, "wifiForget:saved-test")
        button.clicked()
        compare(controls.confirmUuid, "saved-test")
        wifi.profiles = [{uuid:"saved-test",name:"Not nearby",ssid:"Not nearby",active:true}]
        verify(!findChild(controls, "wifiForget:saved-test").enabled)
        wifi.forgetProfile("saved-test")
        verify(!wifi.busy)
    }
}
