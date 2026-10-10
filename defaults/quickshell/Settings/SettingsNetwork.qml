pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../Components"

ColumnLayout {
    id: root
    required property var theme
    required property var backend
    readonly property bool ready: backend !== null && backend.ready
    readonly property bool busy: !backend || backend.busy
    property string selectedPath: ""
    property var profileSelections: ({})
    readonly property var connections: ready ? backend.connected : []
    readonly property var selected: connections.find(row => row.path === selectedPath) || null
    property var editing: null
    property string provider: "Automatic"
    readonly property bool stale: editing !== null && (!selected || !backend.matches(editing, selected))
    spacing: 12

    function beginEdit() {
        if (!selected) return
        editing = selected
        provider = selected.provider
        ipv4.text = selected.dns["4"].servers.join(", ")
        ipv6.text = selected.dns["6"].servers.join(", ")
    }
    function save() {
        if (!editing || stale || busy) return
        backend.setDns(editing, provider, ipv4.text, ipv6.text)
        editing = null
    }
    onConnectionsChanged: {
        if (!editing && !connections.some(row => row.path === selectedPath))
            selectedPath = (connections.find(row => row.default) || connections[0] || {}).path || ""
    }
    Connections {
        target: root.backend
        function onSettingsActiveChanged() { if (!root.backend.settingsActive) root.editing = null }
    }

    RowLayout {
        SettingsButton { theme: root.theme; text: "Refresh"; enabled: !root.busy; onClicked: root.backend.refresh(true) }
        Text { text: root.busy ? "Working…" : ""; color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize }
    }
    Text {
        Layout.fillWidth: true
        visible: text !== ""
        text: !root.backend ? "NetworkManager is unavailable." : root.backend.error || root.backend.notice || (!root.ready ? "Reading network connections…" : "")
        textFormat: Text.PlainText
        color: root.backend && root.backend.error ? root.theme.critical : root.theme.textMuted
        font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        visible: root.ready && !root.backend.ethernet.length
        text: "No Ethernet adapter detected. Plug in an adapter to see wired connections."
        color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    Repeater {
        model: root.ready ? root.backend.ethernet : []
        delegate: ColumnLayout {
            id: device
            required property var modelData
            readonly property string profile: modelData.profiles.some(row => row.uuid === root.profileSelections[modelData.path])
                ? root.profileSelections[modelData.path] : modelData.profiles.length ? modelData.profiles[0].uuid : ""
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: device.modelData.interface + (device.modelData.name ? " · " + device.modelData.name : "")
                textFormat: Text.PlainText; wrapMode: Text.WordWrap
                color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.textSize; font.weight: Font.DemiBold
            }
            Text {
                Layout.fillWidth: true
                text: !device.modelData.managed ? "Not managed by NetworkManager"
                    : !device.modelData.carrier ? "Cable unplugged"
                    : device.modelData.connected ? "Connected" + (device.modelData.speed ? " · " + device.modelData.speed + " Mbit/s" : "")
                    : device.modelData.activePath !== "/" ? "Connecting…" : "Disconnected"
                color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
            }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                SettingsComboBox {
                    id: profileChoice
                    property var menuProfiles: []
                    property bool selecting: false
                    property var menuDevice: null
                    readonly property var options: selecting ? menuProfiles : device.modelData.profiles
                    objectName: "ethernetProfile:" + device.modelData.path
                    theme: root.theme
                    visible: !device.modelData.connected && device.modelData.profiles.length > 0
                    model: options.map(row => row.name)
                    currentIndex: options.findIndex(row => row.uuid === device.profile)
                    enabled: !root.busy
                    onActivated: index => {
                        const choice = options[index]
                        if (!choice || (selecting && !root.backend.matches(menuDevice, device.modelData))) return
                        const next = Object.assign({}, root.profileSelections)
                        next[device.modelData.path] = choice.uuid
                        root.profileSelections = next
                    }
                    Connections {
                        target: profileChoice.popup
                        function onAboutToShow() {
                            profileChoice.selecting = true
                            profileChoice.menuProfiles = device.modelData.profiles.slice()
                            profileChoice.menuDevice = device.modelData
                        }
                        function onClosed() { Qt.callLater(() => { if (!profileChoice.popup.visible) profileChoice.selecting = false }) }
                    }
                }
                SettingsButton {
                    objectName: "ethernetConnect:" + device.modelData.path
                    theme: root.theme
                    text: device.modelData.connected ? "Disconnect" : device.modelData.profiles.length ? "Connect" : "Connect automatically"
                    enabled: !root.busy && device.modelData.managed && (device.modelData.connected ||
                        (device.modelData.carrier && device.modelData.activePath === "/" && [30, 120].includes(device.modelData.state)))
                    onClicked: device.modelData.connected ? root.backend.disconnectDevice(device.modelData) : root.backend.connectDevice(device.modelData, device.profile)
                }
            }
        }
    }
    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.theme.divider }
    Text { text: "Connection details & DNS"; color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.textSize; font.weight: Font.DemiBold }
    Text {
        Layout.fillWidth: true
        visible: !root.connections.length
        text: "Connect to Ethernet or Wi-Fi to view addresses and change DNS."
        color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap
    }
    SettingsComboBox {
        id: connectionChoice
        property var menuConnections: []
        property bool selecting: false
        readonly property var options: selecting ? menuConnections : root.connections
        objectName: "dnsConnection"
        Layout.fillWidth: true
        visible: root.connections.length > 0
        theme: root.theme
        model: options.map(row => row.name + " · " + row.interface)
        currentIndex: options.findIndex(row => row.path === root.selectedPath)
        enabled: !root.busy && !root.editing
        onActivated: index => {
            const choice = options[index]
            if (choice && root.connections.some(row => root.backend.matches(row, choice)))
                root.selectedPath = choice.path
        }
        Connections {
            target: connectionChoice.popup
            function onAboutToShow() { connectionChoice.menuConnections = root.connections.slice(); connectionChoice.selecting = true }
            function onClosed() { Qt.callLater(() => { if (!connectionChoice.popup.visible) connectionChoice.selecting = false }) }
        }
    }
    Repeater {
        model: root.selected ? [4, 6] : []
        delegate: Text {
            required property int modelData
            Layout.fillWidth: true
            text: {
                const ip = root.selected ? root.selected["ipv" + modelData] : {addresses: [], gateway: "", dns: []}
                return "IPv" + modelData + ": " + (ip.addresses.join(", ") || "Not assigned")
                    + "\nGateway: " + (ip.gateway || "None") + "\nDNS servers: " + (ip.dns.join(", ") || "None")
            }
            textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere
            color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
        }
    }
    RowLayout {
        visible: root.selected !== null && root.editing === null
        Text {
            Layout.fillWidth: true
            text: "Saved DNS: " + (root.selected ? root.selected.provider : "")
            color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
        }
        SettingsButton {
            objectName: "dnsEdit"
            theme: root.theme; text: "Change DNS"; enabled: !root.busy
            onClicked: root.beginEdit()
        }
    }
    ColumnLayout {
        visible: root.editing !== null
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: root.stale ? "This connection changed. Cancel and select the active connection again."
                : "DNS for " + (root.editing ? root.editing.name + " · " + root.editing.interface : "")
            textFormat: Text.PlainText; wrapMode: Text.WordWrap
            color: root.stale ? root.theme.critical : root.theme.text
            font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
        }
        SettingsComboBox {
            objectName: "dnsProvider"
            Layout.fillWidth: true
            theme: root.theme
            model: root.backend ? root.backend.providers : []
            currentIndex: model.indexOf(root.provider)
            enabled: !root.busy && !root.stale
            onActivated: index => root.provider = model[index]
        }
        ControlTextField {
            id: ipv4
            objectName: "dnsIPv4"
            Layout.fillWidth: true
            theme: root.theme
            visible: root.provider === "Custom" && root.editing !== null && root.editing.dns["4"].enabled
            placeholderText: "IPv4 DNS servers, separated by commas"
            Accessible.name: "IPv4 DNS servers"
            enabled: !root.busy && !root.stale
        }
        ControlTextField {
            id: ipv6
            objectName: "dnsIPv6"
            Layout.fillWidth: true
            theme: root.theme
            visible: root.provider === "Custom" && root.editing !== null && root.editing.dns["6"].enabled
            placeholderText: "IPv6 DNS servers, separated by commas"
            Accessible.name: "IPv6 DNS servers"
            enabled: !root.busy && !root.stale
        }
        RowLayout {
            SettingsButton { objectName: "dnsSave"; theme: root.theme; text: "Apply DNS"; enabled: !root.busy && !root.stale; onClicked: root.save() }
            SettingsButton { theme: root.theme; text: "Cancel"; enabled: !root.busy; onClicked: root.editing = null }
        }
    }
    Text {
        Layout.fillWidth: true
        visible: root.selected !== null
        text: "Automatic uses DNS supplied by this network. Changes are saved to the selected connection and applied without reconnecting. VPNs and other active connections may also supply DNS."
        color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap
    }
}
