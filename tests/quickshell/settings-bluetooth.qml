import QtQuick
import Quickshell
import Quickshell.Bluetooth
import "Services"
import "Settings"
import "Modules"

ShellRoot {
    id: test
    property int step: 0
    readonly property string deviceKey: "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"
    Theme { id: theme }
    QtObject {
        id: fakeAdapter
        property bool enabled: true
        property bool discovering: false
    }
    QtObject {
        id: device
        property var adapter: fakeAdapter
        property string dbusPath: test.deviceKey
        property string address: "AA:BB:CC:DD:EE:FF"
        property string deviceName: "Test headset"
        property string name: deviceName
        property string icon: "audio-headset"
        property bool connected: false
        property bool paired: true
        property bool bonded: true
        property bool trusted: true
        property bool pairing: false
        property bool blocked: false
        property int state: 0
        property bool batteryAvailable: true
        property real battery: .5
    }
    QtObject {
        id: provider
        property var defaultAdapter: fakeAdapter
        property QtObject devices: QtObject { property var values: [device] }
    }
    QtObject { id: audio; property QtObject nodes: QtObject { property var values: [] }; property var preferredDefaultAudioSink: null }
    BluetoothService {
        id: bluetooth
        provider: provider
        audioProvider: audio
        helper: Qt.resolvedUrl("action.py").toString().replace("file://", "")
        powerHelper: "/missing/bluetooth-power.sh"
        discoveryInterval: 20
    }
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 680
        implicitHeight: 1000
        property bool atBottom: false
        function setVisibilityHold(owner, held) {}
        function hideTooltip(owner) {}
        function showTooltip(owner, text) {}
        SettingsBluetooth { id: controls; theme: theme; backend: bluetooth; width: 620 }
        BluetoothWidget { theme: theme; bar: window; bluetooth: bluetooth; visible: false }
    }
    function check(value, message) { if (!value) throw new Error("Step " + step + ": " + message) }
    function findChild(parent, name) {
        if (parent.objectName === name) return parent
        for (const child of parent.children || []) { const found = findChild(child, name); if (found) return found }
        return null
    }
    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            try {
                switch (test.step) {
                case 0:
                    bluetooth.settingsActive = true
                    test.check(fakeAdapter.discovering, "Settings did not start discovery")
                    bluetooth.setScanRequest("bar", true)
                    bluetooth.settingsActive = false
                    test.check(fakeAdapter.discovering, "Closing Settings stopped the bar's discovery")
                    bluetooth.setScanRequest("bar", false)
                    test.check(!fakeAdapter.discovering, "Last owner did not stop discovery")
                    fakeAdapter.discovering = true // A late start reply must be stopped too.
                    break
                case 1:
                    test.check(!fakeAdapter.discovering, "Late discovery was left active")
                    bluetooth.settingsActive = true
                    test.check(bluetooth.deviceRows.length === 1, "Device discovery failed")
                    const snapshot = bluetooth.deviceRows[0].device
                    device.deviceName = "Renamed headset"
                    test.check(snapshot.name === "Test headset", "Device rows retain live wrappers")
                    bluetooth.connectDevice("/org/bluez/hci1/dev_AA_BB_CC_DD_EE_FF", controls)
                    test.check(!bluetooth.busy, "Wrong adapter target was accepted")
                    bluetooth.connectDevice(test.deviceKey, controls)
                    test.check(bluetooth.busy && !device.connected, "Connection was optimistic")
                    break
                case 2:
                    if (bluetooth.busy) return
                    test.check(!bluetooth.error, "Successful helper reported an error")
                    device.connected = true
                    test.check(findChild(controls, "bluetoothConnect:" + test.deviceKey).text === "Disconnect", "External state not reflected")
                    device.connected = false
                    device.dbusPath = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_00"
                    bluetooth.connectDevice(device.dbusPath, controls)
                    break
                case 3:
                    if (bluetooth.busy) return
                    test.check(bluetooth.error.includes("refused"), "Failure was swallowed")
                    device.dbusPath = test.deviceKey
                    device.paired = false; device.bonded = false; device.trusted = false
                    bluetooth.connectDevice(test.deviceKey, controls)
                    break
                case 4:
                    if (!bluetooth.prompt) return
                    test.check(bluetooth.prompt.code === "012345", "Pairing prompt missing")
                    findChild(controls, "bluetoothPairingConfirm").clicked()
                    break
                case 5:
                    if (bluetooth.busy) return
                    test.check(!bluetooth.error && bluetooth.prompt === null, "Confirmed pairing failed")
                    bluetooth.connectDevice(test.deviceKey, controls)
                    break
                case 6:
                    if (!bluetooth.prompt) return
                    bluetooth.settingsActive = false
                    break
                case 7:
                    if (bluetooth.busy) return
                    test.check(bluetooth.error.includes("canceled"), "Hidden Settings did not cancel pairing")
                    test.check(!fakeAdapter.discovering, "Hidden Settings left discovery active")
                    bluetooth.settingsActive = true
                    device.paired = true
                    const button = findChild(controls, "bluetoothForget:" + test.deviceKey)
                    button.clicked()
                    test.check(!bluetooth.busy && controls.confirmKey === test.deviceKey, "Forget skipped confirmation")
                    button.clicked()
                    break
                case 8:
                    if (bluetooth.busy) return
                    test.check(!bluetooth.error, "Forget failed")
                    bluetooth.togglePower()
                    break
                case 9:
                    if (bluetooth.busy) return
                    test.check(bluetooth.error.length > 0, "Power failure missing")
                    test.check(fakeAdapter.enabled, "Power changed optimistically")
                    provider.defaultAdapter = null
                    test.check(!findChild(controls, "bluetoothPower").enabled, "Missing adapter not handled")
                    test.check(!fakeAdapter.discovering, "Hotplug left discovery active")
                    break
                default:
                    console.log("SETTINGS_BLUETOOTH_PASSED")
                    Qt.quit()
                }
                test.step++
            } catch (error) { console.error(String(error), error.stack); Qt.quit() }
        }
    }
}
