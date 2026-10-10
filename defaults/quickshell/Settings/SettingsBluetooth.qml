pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../Components"

ColumnLayout {
    id: root
    required property var theme
    required property var backend
    property string confirmKey: ""
    readonly property bool active: backend !== null && backend.settingsActive
    spacing: 12
    onActiveChanged: if (!active) { confirmKey = ""; if (backend) backend.cancelForOwner(root) }
    Component.onDestruction: if (backend) backend.cancelForOwner(root)
    Flow {
        Layout.fillWidth: true
        spacing: 8
        SettingsButton {
            objectName: "bluetoothPower"
            theme: root.theme
            text: root.backend && root.backend.enabled ? "Bluetooth: On" : "Bluetooth: Off"
            selected: root.backend !== null && root.backend.enabled
            enabled: root.backend !== null && root.backend.adapter !== null && !root.backend.busy
            onClicked: root.backend.togglePower()
        }
        SettingsButton {
            objectName: "bluetoothScan"
            theme: root.theme
            text: root.backend && root.backend.settingsScanning ? "Pause discovery" : "Find devices"
            enabled: root.backend !== null && root.backend.enabled
            onClicked: root.backend.settingsScanning = !root.backend.settingsScanning
        }
        SettingsButton {
            theme: root.theme
            text: "Cancel pairing"
            visible: root.backend !== null && root.backend.actionKind === "pair" && root.backend.actionOwner === root && root.backend.prompt === null
            enabled: root.backend !== null && !root.backend.cancelled
            onClicked: root.backend.cancelPairing()
        }
    }
    Text {
        Layout.fillWidth: true
        objectName: "bluetoothStatus"
        text: !root.backend || !root.backend.adapter ? "No Bluetooth adapter detected."
            : !root.backend.enabled ? "Bluetooth is off or blocked by a hardware switch."
            : root.backend.actionKind ? "Bluetooth request in progress…"
            : root.backend.settingsScanning ? "Looking for nearby devices…" : "Discovery paused."
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        visible: text !== ""
        text: root.backend ? root.backend.error : ""
        textFormat: Text.PlainText
        color: root.theme.critical
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    BluetoothPairing { Layout.fillWidth: true; theme: root.theme; backend: root.backend; owner: root }
    Repeater {
        model: root.backend && root.backend.enabled ? root.backend.deviceRows : []
        delegate: ColumnLayout {
            id: deviceRow
            required property var modelData
            readonly property var device: modelData.device
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: deviceRow.device.name
                textFormat: Text.PlainText
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.textSize
                font.weight: deviceRow.device.connected ? Font.DemiBold : Font.Normal
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                text: deviceRow.device.address + " · " + (deviceRow.device.blocked ? "Blocked"
                    : deviceRow.device.connected ? "Connected" : deviceRow.device.paired || deviceRow.device.bonded ? "Paired" : "Available")
                    + (deviceRow.device.batteryAvailable ? " · " + Math.round(deviceRow.device.battery * 100) + "% battery" : "")
                color: root.theme.textMuted
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.smallTextSize
                wrapMode: Text.WordWrap
            }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                SettingsButton {
                    objectName: "bluetoothConnect:" + deviceRow.device.key
                    theme: root.theme
                    text: deviceRow.device.connected ? "Disconnect" : deviceRow.device.paired || deviceRow.device.bonded ? "Connect" : "Pair & connect"
                    enabled: !root.backend.busy && !deviceRow.device.blocked && !deviceRow.device.pairing
                    onClicked: deviceRow.device.connected ? root.backend.runAction("disconnect", deviceRow.device.key, root)
                        : root.backend.connectDevice(deviceRow.device.key, root)
                }
                SettingsButton {
                    objectName: "bluetoothForget:" + deviceRow.device.key
                    theme: root.theme
                    visible: deviceRow.device.paired || deviceRow.device.bonded || deviceRow.device.trusted
                    text: root.confirmKey === deviceRow.device.key ? "Confirm forget" : "Forget"
                    enabled: !root.backend.busy
                    onClicked: {
                        if (root.confirmKey === deviceRow.device.key) {
                            root.backend.runAction("forget", deviceRow.device.key, root)
                            root.confirmKey = ""
                        } else { root.confirmKey = deviceRow.device.key; confirmTimer.restart() }
                    }
                }
            }
            Item { implicitHeight: 4 }
        }
    }
    Text {
        Layout.fillWidth: true
        text: "Put your accessory in pairing mode to find it. Forgetting removes its pairing and disconnects it. Connected Bluetooth audio devices become the preferred sound output."
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    Timer { id: confirmTimer; interval: 5000; onTriggered: root.confirmKey = "" }
}
