import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import "../Components"

WidgetFrame {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var rawDevices: Bluetooth.devices ? Bluetooth.devices.values : []
    readonly property var pipewireNodes: Pipewire.nodes ? Pipewire.nodes.values : []
    readonly property string shellDir: Quickshell.env("HOME") + "/.local/share/blankweave/shell"
    readonly property bool enabled: adapter && adapter.enabled

    property var pendingActions: ({})
    property var pendingAudioDevice: null
    property int pendingAudioAttempts: 0
    property bool owesDiscoveryStop: false
    property bool scanPaused: false

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
            "name": root.deviceLabel(device),
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
            if (!device || !root.humanName(device))
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

    function flattenedDeviceRow(item) {
        const row = item.device
        return {
            "section": item.section,
            "address": row.address,
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
        return index === 0 || String(deviceListModel.get(index - 1).section || "") !== section
    }

    function liveDevice(address) {
        for (let index = 0; index < rawDevices.length; index++) {
            if (rawDevices[index] && String(rawDevices[index].address || "") === address)
                return rawDevices[index]
        }
        return null
    }

    function pendingAction(address) {
        return String(pendingActions[address] || "")
    }

    function setPendingAction(address, action) {
        const next = ({})
        for (const key in pendingActions)
            next[key] = pendingActions[key]
        if (action)
            next[address] = action
        else
            delete next[address]
        pendingActions = next
        if (action)
            pendingTimeout.restart()
    }

    function runDeviceAction(device, action, pending) {
        if (!device || !device.address)
            return
        root.setPendingAction(device.address, pending)
        root.bar.run([root.shellDir + "/bluetooth-device.sh", action, device.address])
    }

    function connectDevice(row) {
        const device = root.liveDevice(row.address)
        if (!device || device.connected)
            return
        if (row.paired || row.bonded || row.trusted)
            root.runDeviceAction(row, "connect", "connecting")
        else
            root.runDeviceAction(row, "pair", "pairing")
    }

    function disconnectDevice(row) {
        const device = root.liveDevice(row.address)
        if (!device || !device.connected)
            return
        root.runDeviceAction(row, "disconnect", "disconnecting")
    }

    function cancelPairing(row) {
        const device = root.liveDevice(row.address)
        if (device && device.cancelPair)
            device.cancelPair()
        root.setPendingAction(row.address, "")
    }

    function forgetDevice(row) {
        root.runDeviceAction(row, "forget", "forgetting")
    }

    function togglePower() {
        if (!adapter)
            return
        root.bar.run([
            root.shellDir + "/bluetooth-power.sh",
            adapter.enabled ? "off" : "on"
        ])
    }

    function normalizedAddress(value) {
        return String(value || "").toLowerCase().replace(/[^0-9a-f]/g, "")
    }

    function nodeText(node) {
        const properties = node && node.ready && node.properties ? node.properties : ({})
        return [
            node ? node.name : "",
            node ? node.description : "",
            node ? node.nickname : "",
            properties["node.name"],
            properties["node.description"],
            properties["device.name"],
            properties["device.description"],
            properties["api.bluez5.address"],
            properties["bluez5.address"]
        ].join(" ").toLowerCase()
    }

    function bluetoothSink(device) {
        const address = root.normalizedAddress(device ? device.address : "")
        const label = String(device && device.name || "").toLowerCase()

        for (let index = 0; index < pipewireNodes.length; index++) {
            const node = pipewireNodes[index]
            if (!node || !node.isSink || node.isStream)
                continue
            const text = root.nodeText(node)
            if ((address && root.normalizedAddress(text).includes(address)) || (label && text.includes(label)))
                return node
        }
        return null
    }

    function scheduleAudioSwitch(device) {
        root.pendingAudioDevice = { "address": device.address, "name": device.name }
        root.pendingAudioAttempts = 0
        audioSwitchTimer.restart()
    }

    function switchAudioOutput() {
        if (!pendingAudioDevice)
            return

        const sink = root.bluetoothSink(pendingAudioDevice)
        if (sink) {
            Pipewire.preferredDefaultAudioSink = sink
            if (sink.id !== undefined && sink.name) {
                root.bar.run([
                    root.shellDir + "/audio-output-default.sh",
                    String(sink.id),
                    String(sink.name)
                ])
            }
            root.pendingAudioDevice = null
            return
        }

        root.pendingAudioAttempts += 1
        if (root.pendingAudioAttempts < 8)
            audioSwitchTimer.restart()
        else
            root.pendingAudioDevice = null
    }

    function syncPendingActions() {
        const addresses = Object.keys(pendingActions)
        for (let index = 0; index < addresses.length; index++) {
            const address = addresses[index]
            const action = root.pendingAction(address)
            const device = root.liveDevice(address)
            const connected = device && device.connected
            const remembered = device && (device.paired || device.bonded || device.trusted)

            if (action === "connecting" && connected) {
                root.setPendingAction(address, "")
                root.scheduleAudioSwitch(root.deviceSnapshot(device))
            }
            else if (action === "pairing" && connected) {
                root.setPendingAction(address, "")
                root.scheduleAudioSwitch(root.deviceSnapshot(device))
            }
            else if (action === "disconnecting" && device && !connected) {
                root.setPendingAction(address, "")
            }
            else if (action === "forgetting" && (!device || !remembered)) {
                root.setPendingAction(address, "")
            }
        }
    }

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

    PwObjectTracker {
        objects: root.pipewireNodes
    }

    onDeviceGroupsChanged: root.syncPendingActions()
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

    Timer {
        id: discoveryRetry
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: bluetoothPanel.open && !root.scanPaused && root.enabled && root.adapter && !root.adapter.discovering
        onTriggered: {
            root.owesDiscoveryStop = true
            root.adapter.discovering = true
        }
    }

    Timer {
        id: discoveryStop
        property int attempts: 0
        interval: 700
        repeat: true
        running: !bluetoothPanel.open && root.owesDiscoveryStop && root.adapter && root.adapter.discovering
        onRunningChanged: if (running) attempts = 0
        onTriggered: {
            attempts += 1
            if (attempts > 3) {
                root.owesDiscoveryStop = false
                return
            }
            root.adapter.discovering = false
        }
    }

    Connections {
        target: root.adapter
        function onDiscoveringChanged() {
            if (root.adapter && !root.adapter.discovering && !bluetoothPanel.open)
                root.owesDiscoveryStop = false
        }
    }

    Timer {
        id: pendingTimeout
        interval: 30000
        onTriggered: root.pendingActions = ({})
    }

    Timer {
        id: audioSwitchTimer
        interval: 500
        onTriggered: root.switchAudioOutput()
    }

    ControlPopup {
        id: bluetoothPanel
        bar: root.bar
        theme: root.theme
        anchorItem: root
        panelWidth: 380

        onOpenChanged: {
            root.scanPaused = false
            if (open && root.adapter && root.adapter.discovering) {
                root.owesDiscoveryStop = true
            }
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
                    { "id": "scan", "icon": "󰂰", "active": Boolean(root.adapter && root.adapter.discovering) },
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
                    if (root.adapter.discovering) {
                        root.scanPaused = true
                        root.adapter.discovering = false
                        root.owesDiscoveryStop = false
                    }
                    else {
                        root.scanPaused = false
                        root.owesDiscoveryStop = true
                        root.adapter.discovering = true
                    }
                }
            }
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
                                enabled: !deviceDelegate.busy || deviceDelegate.pending === "pairing"
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
        if (root.owesDiscoveryStop && root.adapter && root.adapter.discovering)
            root.adapter.discovering = false
    }
}
