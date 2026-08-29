import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "../Components"
import "../Services"

WidgetFrame {
    id: root

    readonly property string shellDir: Quickshell.env("HOME") + "/.local/share/hyprarch/shell"
    readonly property string statusScript: shellDir + "/network-status.sh"
    readonly property var networkDevices: Networking.devices ? Networking.devices.values : []
    readonly property var wifiDevice: findDevice(DeviceType.Wifi)
    readonly property var wiredDevice: findDevice(DeviceType.Wired)
    readonly property var wifiNetworkObjects: wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
    readonly property var connectedWifiNetwork: findConnectedWifiNetwork()
    readonly property string kind: wiredDevice && wiredDevice.connected
        ? "ethernet"
        : (connectedWifiNetwork ? "wifi" : "disconnected")
    readonly property int signalStrength: connectedWifiNetwork
        ? Math.round(Number(connectedWifiNetwork.signalStrength || 0) * 100)
        : -1

    property var info: ({
        "text": "Offline",
        "tooltip": "No network connection",
        "interface": "",
        "connection": "",
        "ip": "",
        "gateway": "",
        "download": "0 B/s",
        "upload": "0 B/s"
    })
    property var scannerDevice: null
    property bool scanPaused: false
    property string actionSsid: ""
    property string actionKind: ""
    property string failureSsid: ""
    property string failureReason: ""
    property string passwordSsid: ""
    property string passwordText: ""
    property string identityText: ""
    property var publicInfo: ({ "ipv4": "", "ipv6": "" })
    property string publicInterface: ""
    property bool publicLookupDone: false
    property var dnsInfo: ({
        "provider": "",
        "servers": "",
        "ipv4Servers": "",
        "ipv6Servers": "",
        "error": ""
    })
    property string pendingDnsProvider: ""
    readonly property var dnsProviders: [
        "ISP Default",
        "Cloudflare",
        "Google",
        "Quad9",
        "OpenDNS"
    ]
    readonly property bool busy: actionKind !== ""

    function findDevice(type) {
        let fallback = null
        for (let index = 0; index < networkDevices.length; index++) {
            const device = networkDevices[index]
            if (!device || device.type !== type)
                continue
            if (device.connected)
                return device
            if (!fallback)
                fallback = device
        }
        return fallback
    }

    function findConnectedWifiNetwork() {
        for (let index = 0; index < wifiNetworkObjects.length; index++) {
            if (wifiNetworkObjects[index] && wifiNetworkObjects[index].connected)
                return wifiNetworkObjects[index]
        }
        return null
    }

    function wifiIcon(strength) {
        if (strength < 20) return "󰤯"
        if (strength < 40) return "󰤟"
        if (strength < 60) return "󰤢"
        if (strength < 80) return "󰤥"
        return "󰤨"
    }

    function networkSnapshot(network) {
        return {
            "ssid": String(network.name || ""),
            "connected": Boolean(network.connected),
            "known": Boolean(network.known),
            "stateChanging": Boolean(network.stateChanging),
            "signal": Math.round(Number(network.signalStrength || 0) * 100),
            "security": Number(network.security)
        }
    }

    readonly property var wifiRows: {
        const rows = []
        for (let index = 0; index < wifiNetworkObjects.length; index++) {
            const network = wifiNetworkObjects[index]
            if (!network || !String(network.name || ""))
                continue
            rows.push(root.networkSnapshot(network))
        }
        rows.sort((left, right) => {
            if (left.connected !== right.connected) return left.connected ? -1 : 1
            if (left.known !== right.known) return left.known ? -1 : 1
            if (left.signal !== right.signal) return right.signal - left.signal
            return left.ssid.localeCompare(right.ssid)
        })
        return rows
    }

    function flattenedWifiRow(row) {
        return {
            "ssid": row.ssid,
            "connected": row.connected,
            "known": row.known,
            "stateChanging": row.stateChanging,
            "signal": row.signal,
            "security": row.security
        }
    }

    function syncWifiModel() {
        const desired = root.wifiRows
        const names = ({})
        for (let index = 0; index < desired.length; index++)
            names[desired[index].ssid] = true

        for (let index = wifiListModel.count - 1; index >= 0; index--) {
            if (!names[String(wifiListModel.get(index).ssid || "")])
                wifiListModel.remove(index)
        }

        for (let index = 0; index < desired.length; index++) {
            const entry = root.flattenedWifiRow(desired[index])
            let currentIndex = -1
            for (let candidate = index; candidate < wifiListModel.count; candidate++) {
                if (wifiListModel.get(candidate).ssid === entry.ssid) {
                    currentIndex = candidate
                    break
                }
            }

            if (currentIndex < 0) {
                wifiListModel.insert(index, entry)
            }
            else {
                if (currentIndex !== index)
                    wifiListModel.move(currentIndex, index, 1)
                wifiListModel.set(index, entry)
            }
        }
    }

    function sectionTitle(index, known) {
        if (index === 0)
            return known ? "KNOWN NETWORKS" : "OTHER NETWORKS"
        return Boolean(wifiListModel.get(index - 1).known) !== known ? "OTHER NETWORKS" : ""
    }

    function networkForSsid(ssid) {
        for (let index = 0; index < wifiNetworkObjects.length; index++) {
            const network = wifiNetworkObjects[index]
            if (network && String(network.name || "") === ssid)
                return network
        }
        return null
    }

    function requiresCredentials(security) {
        return security !== WifiSecurityType.Open && security !== WifiSecurityType.Owe
    }

    function isEnterprise(security) {
        return security === WifiSecurityType.Wpa2Eap || security === WifiSecurityType.WpaEap
    }

    function setScannerEnabled(value) {
        const nextDevice = networkPanel.open ? wifiDevice : null
        if (scannerDevice && scannerDevice !== nextDevice)
            scannerDevice.scannerEnabled = false
        scannerDevice = nextDevice
        if (scannerDevice)
            scannerDevice.scannerEnabled = value
    }

    function openPasswordPrompt(ssid) {
        if (passwordSsid !== ssid) {
            passwordText = ""
            identityText = ""
        }
        passwordSsid = ssid
        failureSsid = ""
        failureReason = ""
        Qt.callLater(() => {
            const index = root.modelIndexForSsid(ssid)
            if (index >= 0)
                networkList.positionViewAtIndex(index, ListView.Contain)
        })
    }

    function cancelPasswordPrompt() {
        passwordSsid = ""
        passwordText = ""
        identityText = ""
    }

    function modelIndexForSsid(ssid) {
        for (let index = 0; index < wifiListModel.count; index++) {
            if (wifiListModel.get(index).ssid === ssid)
                return index
        }
        return -1
    }

    function startAction(kind, ssid) {
        if (busy || !ssid)
            return false
        actionKind = kind
        actionSsid = ssid
        failureSsid = ""
        failureReason = ""
        actionTimeout.restart()
        return true
    }

    function clearAction() {
        actionTimeout.stop()
        actionKind = ""
        actionSsid = ""
        root.cancelPasswordPrompt()
    }

    function failAction(ssid, message) {
        actionTimeout.stop()
        failureSsid = ssid
        failureReason = message
        actionKind = ""
        actionSsid = ""
        failureTimer.restart()
    }

    function connectDirectly(ssid) {
        const network = root.networkForSsid(ssid)
        if (!network || !root.startAction("connect", ssid))
            return
        network.connect()
    }

    function connectWithPassword(ssid, password, identity) {
        const network = root.networkForSsid(ssid)
        if (!network || !password || !root.startAction("connect", ssid))
            return

        if (root.isEnterprise(Number(network.security))) {
            if (!identity) {
                root.failAction(ssid, "Identity required")
                root.openPasswordPrompt(ssid)
                return
            }
            enterpriseConnect.secret = password
            enterpriseConnect.command = [
                root.shellDir + "/wifi-enterprise-connect.sh",
                ssid,
                identity
            ]
            enterpriseConnect.running = true
        }
        else {
            network.connectWithPsk(password)
        }
    }

    function disconnectNetwork(ssid) {
        const network = root.networkForSsid(ssid)
        if (!network || !root.startAction("disconnect", ssid))
            return
        network.disconnect()
    }

    function forgetNetwork(ssid) {
        const network = root.networkForSsid(ssid)
        if (!network || !root.startAction("forget", ssid))
            return
        network.forget()
    }

    function checkActionCompletion() {
        if (!actionKind || !actionSsid)
            return
        const network = root.networkForSsid(actionSsid)
        if (actionKind === "connect" && network && network.connected)
            root.clearAction()
        else if (actionKind === "disconnect" && network && !network.connected && !network.stateChanging)
            root.clearAction()
        else if (actionKind === "forget" && (!network || (!network.known && !network.stateChanging)))
            root.clearAction()
    }

    function failureMessage(reason) {
        if (reason === ConnectionFailReason.NoSecrets) return "Passphrase required"
        if (reason === ConnectionFailReason.WifiAuthTimeout) return "Wrong password"
        if (reason === ConnectionFailReason.WifiNetworkLost) return "Network lost"
        if (reason === ConnectionFailReason.WifiClientDisconnected) return "Disconnected"
        return "Connection failed"
    }

    function rowStatus(ssid, connected, known, signal) {
        if (actionSsid === ssid) {
            if (actionKind === "connect") return "Connecting…"
            if (actionKind === "disconnect") return "Disconnecting…"
            if (actionKind === "forget") return "Forgetting…"
        }
        if (failureSsid === ssid && failureReason) return failureReason
        if (connected) return "Connected · " + signal + "%"
        if (known) return "Saved · " + signal + "%"
        return signal + "%"
    }

    function refreshPublicAddresses() {
        if (!info.interface || publicLookup.running)
            return
        publicInterface = String(info.interface)
        publicLookupDone = false
        publicLookup.command = [root.shellDir + "/network-public-ip.sh"]
        publicLookup.running = true
    }

    function updatePublicAddresses(payload) {
        try {
            const parsed = JSON.parse(String(payload || ""))
            publicInfo = {
                "ipv4": String(parsed.ipv4 || ""),
                "ipv6": String(parsed.ipv6 || "")
            }
        } catch (error) {
            publicInfo = ({ "ipv4": "", "ipv6": "" })
        }
        publicLookupDone = true
    }

    function refreshDns() {
        if (!info.interface || dnsProcess.running)
            return
        dnsProcess.command = [root.shellDir + "/network-dns.sh", "status"]
        dnsProcess.running = true
    }

    function setDns(provider) {
        if (!provider || dnsProcess.running)
            return
        pendingDnsProvider = provider
        dnsInfo = {
            "provider": String(dnsInfo.provider || ""),
            "servers": String(dnsInfo.servers || ""),
            "ipv4Servers": String(dnsInfo.ipv4Servers || ""),
            "ipv6Servers": String(dnsInfo.ipv6Servers || ""),
            "error": ""
        }
        dnsProcess.command = [root.shellDir + "/network-dns.sh", provider]
        dnsProcess.running = true
    }

    function updateDns(payload) {
        try {
            dnsInfo = JSON.parse(String(payload || ""))
        } catch (error) {
            dnsInfo = ({
                "provider": String(dnsInfo.provider || ""),
                "servers": String(dnsInfo.servers || ""),
                "ipv4Servers": String(dnsInfo.ipv4Servers || ""),
                "ipv6Servers": String(dnsInfo.ipv6Servers || ""),
                "error": "Could not read DNS configuration"
            })
        }
        pendingDnsProvider = ""
    }

    readonly property string networkIcon: kind === "ethernet"
        ? "󰈀"
        : (kind === "wifi" ? wifiIcon(signalStrength) : "󰤮")
    readonly property string headerTitle: kind === "ethernet"
        ? "ETHERNET"
        : (kind === "wifi" ? String(connectedWifiNetwork.name || "WI-FI") : "NETWORK")
    readonly property string headerSubtitle: kind === "ethernet"
        ? (String(info.connection || "Connected")
            + (wiredDevice && wiredDevice.linkSpeed ? " · " + wiredDevice.linkSpeed + " Mbit/s" : ""))
        : (kind === "wifi"
            ? signalStrength + "% signal"
            : (wifiDevice && Networking.wifiEnabled ? "Scanning for networks" : "Disconnected"))

    icon: root.networkIcon
    iconPixelSize: theme.barIconSize - 2
    label: String(info.text || "")
    tooltip: String(info.tooltip || "No network connection") + "\nClick for controls"
    attention: kind === "disconnected"

    ScriptPoller {
        command: root.statusScript
        interval: 2500
        onUpdated: payload => {
            if (!payload)
                return
            try {
                root.info = JSON.parse(payload)
            } catch (error) {
                root.info = ({ "text": "Offline", "tooltip": payload })
            }
        }
    }

    onInfoChanged: {
        if (publicInterface && String(info.interface || "") !== publicInterface) {
            publicInfo = ({ "ipv4": "", "ipv6": "" })
            publicLookupDone = false
            publicInterface = ""
        }
    }

    ListModel {
        id: wifiListModel
    }

    onWifiRowsChanged: {
        root.syncWifiModel()
        root.checkActionCompletion()
    }

    onWifiDeviceChanged: {
        root.setScannerEnabled(networkPanel.open && !root.scanPaused && Networking.wifiEnabled)
        root.syncWifiModel()
    }

    Connections {
        target: Networking

        function onWifiEnabledChanged() {
            root.setScannerEnabled(networkPanel.open && !root.scanPaused && Networking.wifiEnabled)
        }
    }

    onPressed: button => {
        if (button === Qt.LeftButton) {
            root.bar.hideTooltip(root)
            networkPanel.open = !networkPanel.open
        }
    }

    Timer {
        id: actionTimeout
        interval: 25000
        onTriggered: root.failAction(root.actionSsid, "Timed out")
    }

    Timer {
        id: failureTimer
        interval: 3000
        onTriggered: {
            root.failureSsid = ""
            root.failureReason = ""
        }
    }

    Process {
        id: enterpriseConnect
        property string secret: ""
        stdinEnabled: true
        onStarted: {
            write(secret + "\n")
            secret = ""
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.failAction(root.actionSsid, "Enterprise login failed")
        }
    }

    Process {
        id: publicLookup

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.updatePublicAddresses(text)
        }
    }

    Process {
        id: dnsProcess

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.updateDns(text)
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && !root.dnsInfo.error) {
                root.dnsInfo = {
                    "provider": String(root.dnsInfo.provider || ""),
                    "servers": String(root.dnsInfo.servers || ""),
                    "ipv4Servers": String(root.dnsInfo.ipv4Servers || ""),
                    "ipv6Servers": String(root.dnsInfo.ipv6Servers || ""),
                    "error": "Could not update DNS configuration"
                }
                root.pendingDnsProvider = ""
            }
        }
    }

    ControlPopup {
        id: networkPanel
        bar: root.bar
        theme: root.theme
        anchorItem: root
        panelWidth: 390

        onOpenChanged: {
            root.scanPaused = false
            root.cancelPasswordPrompt()
            root.setScannerEnabled(open && Networking.wifiEnabled)
            if (open) {
                root.refreshDns()
                if (!root.publicLookupDone || root.publicInterface !== String(root.info.interface || ""))
                    root.refreshPublicAddresses()
            }
        }

        ControlPanelHeader {
            theme: root.theme
            icon: root.networkIcon
            title: root.headerTitle
            subtitle: root.headerSubtitle
            actions: root.wifiDevice
                ? [
                    { "id": "scan", "icon": "󰑓", "active": Boolean(root.wifiDevice.scannerEnabled) },
                    {
                        "id": "power",
                        "icon": Networking.wifiEnabled ? "󰤨" : "󰤭",
                        "attention": !Networking.wifiEnabled
                    }
                ]
                : []
            onActionPressed: actionId => {
                if (actionId === "power") {
                    Networking.wifiEnabled = !Networking.wifiEnabled
                    Qt.callLater(() => root.setScannerEnabled(Networking.wifiEnabled))
                }
                else if (actionId === "scan" && root.wifiDevice) {
                    root.scanPaused = root.wifiDevice.scannerEnabled
                    root.setScannerEnabled(!root.scanPaused)
                }
            }
        }

        ControlDivider { theme: root.theme }

        ControlSectionLabel {
            visible: Boolean(root.info.interface)
            theme: root.theme
            text: "CONNECTION"
        }

        GridLayout {
            visible: Boolean(root.info.interface)
            Layout.fillWidth: true
            columns: 4
            columnSpacing: 12
            rowSpacing: 5

            StatLabel { text: "Receiving" }
            StatValue { text: String(root.info.download || "--") }
            StatLabel { text: "Sending" }
            StatValue { text: String(root.info.upload || "--") }
        }

        ControlSectionLabel {
            visible: Boolean(root.info.interface)
            theme: root.theme
            text: "ADDRESSES"
        }

        ColumnLayout {
            visible: Boolean(root.info.interface)
            Layout.fillWidth: true
            spacing: 1

            ControlCopyRow {
                theme: root.theme
                label: "Local IP"
                value: String(root.info.ip || "Not available")
                copyText: String(root.info.ip || "")
            }

            ControlCopyRow {
                theme: root.theme
                label: "Gateway"
                value: String(root.info.gateway || "Not available")
                copyText: String(root.info.gateway || "")
            }

            ControlCopyRow {
                theme: root.theme
                label: "Public IPv4"
                value: publicLookup.running
                    ? "Looking up…"
                    : String(root.publicInfo.ipv4 || "Not available")
                copyText: String(root.publicInfo.ipv4 || "")
            }

            ControlCopyRow {
                theme: root.theme
                label: "Public IPv6"
                value: publicLookup.running
                    ? "Looking up…"
                    : String(root.publicInfo.ipv6 || "No IPv6 route")
                copyText: String(root.publicInfo.ipv6 || "")
            }
        }

        ControlDivider { visible: Boolean(root.info.interface); theme: root.theme }

        ControlSectionLabel {
            visible: Boolean(root.info.interface)
            theme: root.theme
            text: "DNS PROVIDER"
        }

        RowLayout {
            visible: Boolean(root.info.interface)
            Layout.fillWidth: true
            spacing: 5

            Repeater {
                model: root.dnsProviders

                delegate: ControlChoice {
                    required property string modelData

                    Layout.fillWidth: true
                    theme: root.theme
                    text: modelData === "ISP Default" ? "Default" : modelData
                    selected: root.pendingDnsProvider
                        ? root.pendingDnsProvider === modelData
                        : String(root.dnsInfo.provider || "") === modelData
                    busy: root.pendingDnsProvider === modelData
                    enabled: !dnsProcess.running
                    onPressed: root.setDns(modelData)
                }
            }
        }

        Text {
            visible: Boolean(root.info.interface)
            Layout.fillWidth: true
            text: root.dnsInfo.error
                ? String(root.dnsInfo.error)
                : (dnsProcess.running && !root.pendingDnsProvider
                    ? "Reading active connection…"
                    : (root.dnsInfo.provider
                        ? String(root.dnsInfo.provider)
                            + (root.dnsInfo.ipv4Servers && root.dnsInfo.ipv6Servers
                                ? " · IPv4 + IPv6"
                                : (root.dnsInfo.ipv6Servers ? " · IPv6" : " · IPv4"))
                        : "DNS follows the active connection"))
            color: root.dnsInfo.error ? root.theme.critical : root.theme.textMuted
            elide: Text.ElideRight
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.microTextSize
            renderType: Text.NativeRendering
        }

        ControlDivider { visible: Boolean(root.wifiDevice); theme: root.theme }

        ListView {
            id: networkList
            visible: Boolean(root.wifiDevice) && Networking.wifiEnabled && wifiListModel.count > 0
            Layout.fillWidth: true
            Layout.preferredHeight: visible
                ? ((networkPanel.open && !root.scanPaused) ? 280 : Math.min(contentHeight, 280))
                : 0
            model: wifiListModel
            clip: true
            spacing: 0
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
                id: networkDelegate

                required property int index
                required property string ssid
                required property bool connected
                required property bool known
                required property bool stateChanging
                required property int signal
                required property int security

                property bool confirmForget: false
                readonly property bool passwordOpen: root.passwordSsid === ssid
                readonly property bool enterprise: root.isEnterprise(security)
                readonly property bool secured: root.requiresCredentials(security)
                readonly property bool rowBusy: root.actionSsid === ssid && root.busy
                readonly property string section: root.sectionTitle(index, known)

                width: networkList.width
                height: 46 + (section ? 25 : 0) + (passwordOpen ? (enterprise ? 76 : 40) : 0)

                Connections {
                    target: root.networkForSsid(networkDelegate.ssid)

                    function onConnectionFailed(reason) {
                        if (root.actionSsid !== networkDelegate.ssid || root.actionKind !== "connect")
                            return
                        const message = root.failureMessage(reason)
                        root.failAction(networkDelegate.ssid, message)
                        if (networkDelegate.secured
                                && (reason === ConnectionFailReason.NoSecrets
                                    || reason === ConnectionFailReason.WifiAuthTimeout))
                            root.openPasswordPrompt(networkDelegate.ssid)
                    }

                    function onConnectedChanged() { root.checkActionCompletion() }
                    function onKnownChanged() { root.checkActionCompletion() }
                    function onStateChangingChanged() { root.checkActionCompletion() }
                }

                ControlSectionLabel {
                    visible: networkDelegate.section !== ""
                    anchors.left: parent.left
                    anchors.top: parent.top
                    theme: root.theme
                    text: networkDelegate.section
                }

                Item {
                    id: networkBody
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: networkDelegate.section ? 25 : 0
                    height: 46

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 2
                        height: networkDelegate.connected ? 22 : (networkActionMouse.containsMouse ? 14 : 0)
                        color: root.theme.accentBright

                        Behavior on height { NumberAnimation { duration: 140 } }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        spacing: 10

                        Text {
                            Layout.preferredWidth: 20
                            horizontalAlignment: Text.AlignHCenter
                            text: root.wifiIcon(networkDelegate.signal)
                            color: networkDelegate.connected ? root.theme.accentBright : root.theme.textMuted
                            font.family: root.theme.iconFontFamily
                            font.pixelSize: root.theme.controlIconSize
                            renderType: Text.NativeRendering
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    Layout.fillWidth: true
                                    text: networkDelegate.ssid
                                    color: root.theme.text
                                    elide: Text.ElideRight
                                    font.family: root.theme.fontFamily
                                    font.pixelSize: root.theme.smallTextSize
                                    font.weight: networkDelegate.connected ? Font.DemiBold : Font.Normal
                                    renderType: Text.NativeRendering
                                }

                                Text {
                                    visible: networkDelegate.secured
                                    text: "󰌾"
                                    color: root.theme.textMuted
                                    font.family: root.theme.iconFontFamily
                                    font.pixelSize: root.theme.microTextSize
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.rowStatus(
                                    networkDelegate.ssid,
                                    networkDelegate.connected,
                                    networkDelegate.known,
                                    networkDelegate.signal
                                )
                                color: root.failureSsid === networkDelegate.ssid
                                    ? root.theme.critical
                                    : (networkDelegate.connected ? root.theme.accentBright : root.theme.textMuted)
                                elide: Text.ElideRight
                                font.family: root.theme.fontFamily
                                font.pixelSize: root.theme.microTextSize
                                renderType: Text.NativeRendering
                            }
                        }

                        Item {
                            visible: networkDelegate.known && !networkDelegate.connected && !networkDelegate.rowBusy
                            Layout.preferredWidth: visible ? 52 : 0
                            Layout.preferredHeight: 28

                            Text {
                                anchors.centerIn: parent
                                text: networkDelegate.confirmForget ? "Confirm" : "Forget"
                                color: networkDelegate.confirmForget ? root.theme.critical : root.theme.textMuted
                                font.family: root.theme.fontFamily
                                font.pixelSize: root.theme.microTextSize
                                font.weight: Font.Medium
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (networkDelegate.confirmForget) {
                                        root.forgetNetwork(networkDelegate.ssid)
                                        networkDelegate.confirmForget = false
                                    }
                                    else {
                                        networkDelegate.confirmForget = true
                                        forgetTimer.restart()
                                    }
                                }
                            }
                        }

                        Item {
                            Layout.preferredWidth: 68
                            Layout.preferredHeight: 28
                            opacity: root.busy && !networkDelegate.rowBusy ? 0.45 : 1

                            Text {
                                anchors.centerIn: parent
                                text: networkDelegate.rowBusy
                                    ? (root.actionKind === "connect" ? "Connecting" : "Working")
                                    : (networkDelegate.connected ? "Disconnect" : "Connect")
                                color: networkDelegate.connected ? root.theme.accentBright : root.theme.text
                                font.family: root.theme.fontFamily
                                font.pixelSize: root.theme.microTextSize
                                font.weight: Font.DemiBold
                            }

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                width: networkActionMouse.containsMouse ? 46 : 0
                                height: 1
                                color: root.theme.accentBright

                                Behavior on width { NumberAnimation { duration: 140 } }
                            }

                            MouseArea {
                                id: networkActionMouse
                                anchors.fill: parent
                                enabled: !root.busy
                                hoverEnabled: enabled
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (networkDelegate.connected) {
                                        root.disconnectNetwork(networkDelegate.ssid)
                                    }
                                    else if (networkDelegate.secured && !networkDelegate.known) {
                                        root.openPasswordPrompt(networkDelegate.ssid)
                                    }
                                    else {
                                        root.connectDirectly(networkDelegate.ssid)
                                    }
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    visible: networkDelegate.passwordOpen
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 42
                    spacing: 4

                    ControlTextField {
                        visible: networkDelegate.enterprise
                        Layout.fillWidth: true
                        theme: root.theme
                        placeholderText: "Identity (user@domain)"
                        text: root.identityText
                        onTextChanged: if (networkDelegate.passwordOpen) root.identityText = text
                        onAccepted: passwordField.forceActiveFocus()
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        ControlTextField {
                            id: passwordField
                            Layout.fillWidth: true
                            theme: root.theme
                            secret: true
                            placeholderText: "Passphrase"
                            text: root.passwordText
                            onTextChanged: if (networkDelegate.passwordOpen) root.passwordText = text
                            onAccepted: root.connectWithPassword(
                                networkDelegate.ssid,
                                root.passwordText,
                                root.identityText
                            )
                            Keys.onEscapePressed: root.cancelPasswordPrompt()
                            onVisibleChanged: {
                                if (visible && !networkDelegate.enterprise)
                                    Qt.callLater(() => passwordField.forceActiveFocus())
                            }
                        }

                        Item {
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30

                            Text {
                                anchors.centerIn: parent
                                text: "󰄬"
                                color: root.passwordText ? root.theme.accentBright : root.theme.textMuted
                                font.family: root.theme.iconFontFamily
                                font.pixelSize: root.theme.iconSize
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: root.passwordText !== ""
                                    && (!networkDelegate.enterprise || root.identityText !== "")
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root.connectWithPassword(
                                    networkDelegate.ssid,
                                    root.passwordText,
                                    root.identityText
                                )
                            }
                        }
                    }
                }

                Timer {
                    id: forgetTimer
                    interval: 2500
                    onTriggered: networkDelegate.confirmForget = false
                }
            }
        }

        Text {
            visible: Boolean(root.wifiDevice)
                && (!Networking.wifiEnabled || wifiListModel.count === 0)
            Layout.fillWidth: true
            Layout.preferredHeight: Networking.wifiEnabled && networkPanel.open && !root.scanPaused ? 280 : 42
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            text: !Networking.wifiEnabled ? "Wi-Fi is turned off" : "Scanning for networks…"
            color: root.theme.textMuted
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.smallTextSize
            renderType: Text.NativeRendering
        }
    }

    component StatLabel: Text {
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.microTextSize
        renderType: Text.NativeRendering
    }

    component StatValue: Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignRight
        color: root.theme.text
        elide: Text.ElideRight
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.microTextSize
        font.weight: Font.DemiBold
        renderType: Text.NativeRendering
    }

    Component.onCompleted: root.syncWifiModel()

    Component.onDestruction: {
        if (root.scannerDevice)
            root.scannerDevice.scannerEnabled = false
    }
}
