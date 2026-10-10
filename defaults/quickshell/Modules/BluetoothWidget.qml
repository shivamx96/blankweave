pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../Components"

WidgetFrame {
    id: root

    required property var bluetooth
    readonly property var adapter: bluetooth.adapter
    readonly property bool enabled: bluetooth.enabled
    readonly property var deviceRows: bluetooth.deviceRows
    readonly property var connectedDevices: bluetooth.connectedDevices
    property bool scanPaused: false

    function flattenedDeviceRow(item) {
        const row = item.device
        return {
            "section": item.section,
            "address": row.address,
            "deviceKey": row.key,
            "name": row.name,
            "deviceIconName": row.icon,
            "connected": row.connected,
            "paired": row.paired,
            "bonded": row.bonded,
            "trusted": row.trusted,
            "pairing": row.pairing,
            "deviceState": row.state,
            "batteryAvailable": row.batteryAvailable,
            "battery": row.battery
        }
    }

    function syncDeviceModel() {
        const desired = root.deviceRows
        const addresses = ({})
        for (let index = 0; index < desired.length; index++)
            addresses[desired[index].device.address] = true

        for (let index = deviceListModel.count - 1; index >= 0; index--) {
            if (!addresses[String(deviceListModel.get(index).address || "")])
                deviceListModel.remove(index)
        }

        for (let index = 0; index < desired.length; index++) {
            const entry = root.flattenedDeviceRow(desired[index])
            let currentIndex = -1
            for (let candidate = index; candidate < deviceListModel.count; candidate++) {
                if (deviceListModel.get(candidate).address === entry.address) {
                    currentIndex = candidate
                    break
                }
            }

            if (currentIndex < 0) {
                deviceListModel.insert(index, entry)
            }
            else {
                if (currentIndex !== index)
                    deviceListModel.move(currentIndex, index, 1)
                deviceListModel.set(index, entry)
            }
        }
    }

    function modelSectionStartsAt(index, section) {
        const previous = index > 0 && index <= deviceListModel.count ? deviceListModel.get(index - 1) : null
        return !previous || String(previous.section || "") !== section
    }

    function pendingAction(address) { return bluetooth.pendingAction(address) }
    function connectDevice(row) { bluetooth.connectDevice(row.key, root) }
    function disconnectDevice(row) { bluetooth.runAction("disconnect", row.key, root) }
    function cancelPairing(row) { bluetooth.cancelPairing() }
    function forgetDevice(row) { bluetooth.runAction("forget", row.key, root) }
    function togglePower() { bluetooth.togglePower() }

    function deviceIcon(row) {
        const iconName = String(row.icon || "").toLowerCase()
        if (iconName.includes("headset")) return "󰋎"
        if (iconName.includes("headphone")) return "󰋋"
        if (iconName.includes("keyboard")) return "󰌌"
        if (iconName.includes("mouse")) return "󰍽"
        if (iconName.includes("phone")) return "󰄜"
        if (iconName.includes("computer")) return "󰟀"
        return row.connected ? "󰂱" : "󰂯"
    }

    function statusText(row) {
        const pending = root.pendingAction(row.address)
        if (pending === "pairing") return "Pairing…"
        if (pending === "connecting") return "Connecting…"
        if (pending === "disconnecting") return "Disconnecting…"
        if (pending === "forgetting") return "Forgetting…"
        if (row.pairing) return "Pairing…"
        if (row.connected && row.batteryAvailable) return "Connected · " + Math.round(row.battery * 100) + "%"
        if (row.connected) return "Connected"
        if (row.paired || row.bonded || row.trusted) return "Paired"
        return "Available"
    }

    function primaryActionText(row) {
        const pending = root.pendingAction(row.address)
        if (pending === "pairing") return "Cancel"
        if (pending === "connecting") return "Connecting"
        if (pending === "disconnecting") return "Disconnecting"
        if (pending === "forgetting") return "Forgetting"
        if (row.connected) return "Disconnect"
        if (row.paired || row.bonded || row.trusted) return "Connect"
        return "Pair"
    }

    visible: adapter !== null
    icon: !enabled ? "󰂲" : (connectedDevices.length > 0 ? "󰂱" : "󰂯")
    label: !enabled ? "Off" : (connectedDevices.length > 0 ? String(connectedDevices.length) : "")
    tooltip: !enabled
        ? "Bluetooth disabled\nClick for controls · Right-click to enable"
        : (connectedDevices.length > 0
            ? connectedDevices.map(device => device.name).join("\n") + "\nClick for controls"
            : "Bluetooth enabled · No connected devices\nClick to scan")
    active: connectedDevices.length > 0

    onDeviceRowsChanged: root.syncDeviceModel()

    ListModel {
        id: deviceListModel
    }

    onPressed: button => {
        if (button === Qt.LeftButton) {
            root.bar.hideTooltip(root)
            bluetoothPanel.open = !bluetoothPanel.open
        }
        else if (button === Qt.RightButton) {
            root.togglePower()
        }
    }

    ControlPopup {
        id: bluetoothPanel
        bar: root.bar
        theme: root.theme
        anchorItem: root
        panelWidth: 380

        onOpenChanged: {
            root.scanPaused = false
            root.bluetooth.setScanRequest(root, open)
            if (!open) root.bluetooth.cancelForOwner(root)
        }

        ControlPanelHeader {
            theme: root.theme
            icon: root.icon
            title: "BLUETOOTH"
            subtitle: !root.adapter
                ? "No adapter"
                : (!root.enabled
                    ? "Turned off"
                    : (root.adapter.discovering
                        ? "Scanning for nearby devices"
                        : (root.connectedDevices.length > 0
                            ? root.connectedDevices.length + " connected"
                            : "Ready")))
            actions: root.enabled
                ? [
                    { "id": "scan", "icon": "󰂰", "active": !root.scanPaused && root.enabled },
                    { "id": "power", "icon": "󰂯" }
                ]
                : [
                    { "id": "power", "icon": "󰂲", "attention": true }
                ]
            onActionPressed: actionId => {
                if (actionId === "power") {
                    root.togglePower()
                }
                else if (actionId === "scan" && root.adapter) {
                    root.scanPaused = !root.scanPaused
                    root.bluetooth.setScanRequest(root, !root.scanPaused)
                }
            }
        }

        BluetoothPairing { theme: root.theme; backend: root.bluetooth; owner: root; Layout.fillWidth: true }
        Text {
            Layout.fillWidth: true
            visible: text !== ""
            text: root.bluetooth.error
            textFormat: Text.PlainText
            color: root.theme.critical
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.smallTextSize
            wrapMode: Text.WordWrap
        }
        ControlDivider { theme: root.theme }

        ListView {
            id: deviceList
            visible: root.enabled && deviceListModel.count > 0
            Layout.fillWidth: true
            Layout.preferredHeight: visible
                ? ((bluetoothPanel.open && !root.scanPaused) ? 300 : Math.min(contentHeight, 300))
                : 0
            model: deviceListModel
            clip: true
            spacing: 0
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
                id: deviceDelegate

                required property int index
                required property string section
                required property string deviceKey
                required property string address
                required property string name
                required property string deviceIconName
                required property bool connected
                required property bool paired
                required property bool bonded
                required property bool trusted
                required property bool pairing
                required property int deviceState
                required property bool batteryAvailable
                required property real battery
                property bool confirmForget: false

                readonly property var row: ({
                    "address": address,
                    "key": deviceKey,
                    "name": name,
                    "icon": deviceIconName,
                    "connected": connected,
                    "paired": paired,
                    "bonded": bonded,
                    "trusted": trusted,
                    "pairing": pairing,
                    "state": deviceState,
                    "batteryAvailable": batteryAvailable,
                    "battery": battery
                })
                readonly property bool showSection: root.modelSectionStartsAt(index, section)
                readonly property bool remembered: row.paired || row.bonded || row.trusted
                readonly property string pending: root.pendingAction(row.address)
                readonly property bool busy: pending !== ""

                width: deviceList.width
                height: 46 + (showSection ? 25 : 0)

                ControlSectionLabel {
                    visible: deviceDelegate.showSection
                    anchors.left: parent.left
                    anchors.top: parent.top
                    text: deviceDelegate.section
                    theme: root.theme
                }

                Item {
                    id: deviceBody
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 46

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 2
                        height: deviceDelegate.row.connected ? 22 : (primaryMouse.containsMouse ? 14 : 0)
                        color: root.theme.accentBright

                        Behavior on height {
                            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        spacing: 10

                        Text {
                            Layout.preferredWidth: 20
                            horizontalAlignment: Text.AlignHCenter
                            text: root.deviceIcon(deviceDelegate.row)
                            color: deviceDelegate.row.connected ? root.theme.accentBright : root.theme.textMuted
                            font.family: root.theme.iconFontFamily
                            font.pixelSize: root.theme.controlIconSize
                            renderType: Text.NativeRendering
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                text: deviceDelegate.row.name || "Bluetooth device"
                                color: root.theme.text
                                elide: Text.ElideRight
                                font.family: root.theme.fontFamily
                                font.pixelSize: root.theme.smallTextSize
                                font.weight: deviceDelegate.row.connected ? Font.DemiBold : Font.Normal
                                renderType: Text.NativeRendering
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.statusText(deviceDelegate.row)
                                color: deviceDelegate.row.connected ? root.theme.accentBright : root.theme.textMuted
                                elide: Text.ElideRight
                                font.family: root.theme.fontFamily
                                font.pixelSize: root.theme.microTextSize
                                renderType: Text.NativeRendering
                            }
                        }

                        Item {
                            visible: deviceDelegate.remembered && deviceDelegate.pending !== "forgetting"
                            Layout.preferredWidth: visible ? 52 : 0
                            Layout.preferredHeight: 28

                            Text {
                                anchors.centerIn: parent
                                text: deviceDelegate.confirmForget ? "Confirm" : "Forget"
                                color: deviceDelegate.confirmForget ? root.theme.critical : root.theme.textMuted
                                font.family: root.theme.fontFamily
                                font.pixelSize: root.theme.microTextSize
                                font.weight: Font.Medium
                            }

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                width: forgetMouse.containsMouse || deviceDelegate.confirmForget ? 38 : 0
                                height: 1
                                color: deviceDelegate.confirmForget ? root.theme.critical : root.theme.accentBright

                                Behavior on width { NumberAnimation { duration: 140 } }
                            }

                            MouseArea {
                                id: forgetMouse
                                enabled: !root.bluetooth.busy
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (deviceDelegate.confirmForget) {
                                        root.forgetDevice(deviceDelegate.row)
                                        deviceDelegate.confirmForget = false
                                    }
                                    else {
                                        deviceDelegate.confirmForget = true
                                        forgetConfirmation.restart()
                                    }
                                }
                            }
                        }

                        Item {
                            Layout.preferredWidth: 72
                            Layout.preferredHeight: 28
                            opacity: deviceDelegate.busy && deviceDelegate.pending !== "pairing" ? 0.58 : 1

                            Text {
                                anchors.centerIn: parent
                                text: root.primaryActionText(deviceDelegate.row)
                                color: deviceDelegate.row.connected ? root.theme.accentBright : root.theme.text
                                font.family: root.theme.fontFamily
                                font.pixelSize: root.theme.microTextSize
                                font.weight: Font.DemiBold
                            }

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                width: primaryMouse.containsMouse ? 48 : 0
                                height: 1
                                color: root.theme.accentBright

                                Behavior on width { NumberAnimation { duration: 140 } }
                            }

                            MouseArea {
                                id: primaryMouse
                                anchors.fill: parent
                                enabled: !root.bluetooth.busy || deviceDelegate.pending === "pairing"
                                hoverEnabled: enabled
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (deviceDelegate.pending === "pairing")
                                        root.cancelPairing(deviceDelegate.row)
                                    else if (deviceDelegate.row.connected)
                                        root.disconnectDevice(deviceDelegate.row)
                                    else
                                        root.connectDevice(deviceDelegate.row)
                                }
                            }
                        }
                    }
                }

                Timer {
                    id: forgetConfirmation
                    interval: 2500
                    onTriggered: deviceDelegate.confirmForget = false
                }
            }
        }

        Text {
            visible: !root.enabled || deviceListModel.count === 0
            Layout.fillWidth: true
            Layout.preferredHeight: root.enabled && bluetoothPanel.open && !root.scanPaused ? 300 : 42
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            text: !root.adapter
                ? "No Bluetooth adapter found"
                : (!root.enabled ? "Turn Bluetooth on to scan" : "Scanning for nearby devices…")
            color: root.theme.textMuted
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.smallTextSize
            renderType: Text.NativeRendering
        }
    }

    Component.onCompleted: root.syncDeviceModel()

    Component.onDestruction: {
        if (bluetooth) {
            bluetooth.setScanRequest(root, false)
            bluetooth.cancelForOwner(root)
        }
    }
}
