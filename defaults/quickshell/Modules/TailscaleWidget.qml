import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../Components"
import "../Services"

WidgetFrame {
    id: root

    readonly property string shellDir: Quickshell.env("HOME") + "/.local/share/hyprarch/shell"
    property var status: ({
        "available": false,
        "daemonRunning": false,
        "connected": false,
        "backend": "Loading",
        "hostname": "",
        "dnsName": "",
        "tailnet": "",
        "ipv4": "",
        "ipv6": "",
        "relay": "",
        "exitNode": "",
        "peerCount": 0,
        "onlinePeerCount": 0,
        "hiddenPeerCount": 0,
        "peers": [],
        "error": ""
    })
    property string actionKind: ""
    property string actionOutput: ""
    property string actionError: ""
    readonly property bool running: Boolean(status.daemonRunning)
    readonly property bool connected: Boolean(status.connected)
    readonly property bool busy: actionProcess.running
    readonly property url tailscaleIconSource: Qt.resolvedUrl(
        "../Assets/tailscale-"
            + (connected ? "connected" : "disconnected")
            + "-"
            + (theme.dark ? "dark" : "light")
            + ".svg"
    )

    function updateStatus(payload) {
        if (!payload)
            return
        try {
            root.status = JSON.parse(payload)
            root.syncPeerModel()
        } catch (error) {
            root.status = {
                "available": true,
                "daemonRunning": true,
                "connected": false,
                "backend": "Error",
                "peers": [],
                "error": "Could not read Tailscale status"
            }
            root.syncPeerModel()
        }
    }

    function flattenedPeer(peer) {
        return {
            "peerId": String(peer.id || peer.dnsName || peer.hostname || ""),
            "hostname": String(peer.hostname || "Unknown device"),
            "dnsName": String(peer.dnsName || ""),
            "os": String(peer.os || "unknown"),
            "online": Boolean(peer.online),
            "activeConnection": Boolean(peer.active),
            "exitNode": Boolean(peer.exitNode),
            "ipv4": String(peer.ipv4 || ""),
            "relay": String(peer.relay || ""),
            "lastSeen": String(peer.lastSeen || "")
        }
    }

    function syncPeerModel() {
        const desired = root.status.peers || []
        const identifiers = ({})
        for (let index = 0; index < desired.length; index++)
            identifiers[String(desired[index].id || desired[index].dnsName || desired[index].hostname || "")] = true

        for (let index = peerModel.count - 1; index >= 0; index--) {
            if (!identifiers[String(peerModel.get(index).peerId || "")])
                peerModel.remove(index)
        }

        for (let index = 0; index < desired.length; index++) {
            const entry = root.flattenedPeer(desired[index])
            let currentIndex = -1
            for (let candidate = index; candidate < peerModel.count; candidate++) {
                if (peerModel.get(candidate).peerId === entry.peerId) {
                    currentIndex = candidate
                    break
                }
            }
            if (currentIndex < 0) {
                peerModel.insert(index, entry)
            } else {
                if (currentIndex !== index)
                    peerModel.move(currentIndex, index, 1)
                peerModel.set(index, entry)
            }
        }
    }

    function peerIcon(os) {
        const normalized = String(os || "").toLowerCase()
        if (normalized.includes("mac")) return "󰀵"
        if (normalized.includes("ios")) return "󰀷"
        if (normalized.includes("android")) return "󰀲"
        if (normalized.includes("windows")) return "󰖳"
        if (normalized.includes("linux")) return "󰌽"
        return "󰇅"
    }

    function peerStatus(online, relay, lastSeen) {
        if (online)
            return relay ? "Online · " + relay.toUpperCase() : "Online"
        if (!lastSeen || lastSeen.startsWith("0001-"))
            return "Offline"
        const seen = new Date(lastSeen)
        if (Number.isNaN(seen.getTime()))
            return "Offline"
        return "Seen " + seen.toLocaleDateString(Qt.locale(), "dd MMM")
    }

    function beginConnectionAction(connect) {
        if (actionProcess.running)
            return
        root.actionKind = connect ? "connect" : "disconnect"
        root.actionOutput = ""
        root.actionError = ""
        actionProcess.command = ["tailscale", connect ? "up" : "down"]
        actionProcess.running = true
    }

    visible: running
    iconSource: root.tailscaleIconSource
    iconVisualSize: root.theme.iconSize
    iconOnly: true
    active: connected || tailscalePanel.open
    attention: running && !connected
    tooltip: connected
        ? "Tailscale connected · " + Number(status.onlinePeerCount || 0) + " peers online\nClick for mesh controls"
        : "Tailscale " + String(status.backend || "stopped") + "\nClick for controls"

    ScriptPoller {
        id: statusPoller
        command: root.shellDir + "/tailscale-status.sh"
        interval: tailscalePanel.open ? 4000 : 10000
        onUpdated: payload => root.updateStatus(payload)
    }

    ListModel {
        id: peerModel
    }

    Process {
        id: actionProcess

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.actionOutput = String(text || "").trim()
        }

        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const message = String(text || "").trim()
                if (message)
                    root.actionOutput = message
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.actionError = root.actionOutput || "Tailscale action failed"
            actionSettleTimer.restart()
        }
    }

    Timer {
        id: actionSettleTimer
        interval: 600
        onTriggered: {
            root.actionKind = ""
            statusPoller.refresh()
        }
    }

    onPressed: button => {
        if (button === Qt.LeftButton) {
            root.bar.hideTooltip(root)
            tailscalePanel.open = !tailscalePanel.open
        }
    }

    ControlPopup {
        id: tailscalePanel
        bar: root.bar
        theme: root.theme
        anchorItem: root
        panelWidth: 410

        onOpenChanged: {
            if (open) {
                root.actionError = ""
                statusPoller.refresh()
            }
        }

        ControlPanelHeader {
            theme: root.theme
            iconSource: root.tailscaleIconSource
            title: "TAILSCALE"
            subtitle: root.connected
                ? (String(root.status.tailnet || "Connected") + " · " + String(root.status.hostname || "This device"))
                : (root.busy
                    ? (root.actionKind === "connect" ? "Connecting…" : "Disconnecting…")
                    : String(root.status.backend || "Stopped"))
            actions: [
                { "id": "refresh", "icon": "󰑐", "active": statusPoller.ready },
                { "id": "admin", "icon": "󰖟" },
                {
                    "id": "power",
                    "icon": root.connected ? "󰅖" : "󰐥",
                    "active": root.connected,
                    "attention": !root.connected
                }
            ]
            onActionPressed: actionId => {
                if (actionId === "refresh") {
                    statusPoller.refresh()
                } else if (actionId === "admin") {
                    tailscalePanel.open = false
                    root.bar.run(["xdg-open", "https://login.tailscale.com/admin/machines"])
                } else if (actionId === "power") {
                    root.beginConnectionAction(!root.connected)
                }
            }
        }

        ControlDivider { theme: root.theme }

        ApplicationSummary {
            theme: root.theme
            metrics: [
                {
                    "label": "STATUS",
                    "value": root.connected ? "Online" : "Offline",
                    "active": root.connected,
                    "attention": !root.connected
                },
                {
                    "label": "PEERS",
                    "value": Number(root.status.onlinePeerCount || 0) + " / " + Number(root.status.peerCount || 0)
                },
                {
                    "label": "RELAY",
                    "value": String(root.status.relay || "Direct").toUpperCase()
                }
            ]
        }

        ControlSectionLabel {
            theme: root.theme
            text: "THIS DEVICE"
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            ControlCopyRow {
                theme: root.theme
                label: "MagicDNS"
                value: String(root.status.dnsName || "Not available")
                copyText: String(root.status.dnsName || "")
            }

            ControlCopyRow {
                theme: root.theme
                label: "IPv4"
                value: String(root.status.ipv4 || "Not available")
                copyText: String(root.status.ipv4 || "")
            }

            ControlCopyRow {
                theme: root.theme
                label: "IPv6"
                value: String(root.status.ipv6 || "Not available")
                copyText: String(root.status.ipv6 || "")
            }

            ControlCopyRow {
                visible: Boolean(root.status.exitNode)
                theme: root.theme
                label: "Exit node"
                value: String(root.status.exitNode || "")
                copyText: ""
            }
        }

        ControlDivider { theme: root.theme }

        ControlSectionLabel {
            theme: root.theme
            text: "DEVICES"
        }

        ListView {
            id: peerList
            visible: peerModel.count > 0
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? Math.min(contentHeight, 8 * 44) : 0
            model: peerModel
            clip: true
            spacing: 0
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            delegate: ApplicationListRow {
                id: peerRow

                required property string hostname
                required property string dnsName
                required property string os
                required property bool online
                required property bool activeConnection
                required property bool exitNode
                required property string ipv4
                required property string relay
                required property string lastSeen
                property string copiedAddress: ""

                width: peerList.width
                height: implicitHeight
                rowHeight: 44
                theme: root.theme
                icon: root.peerIcon(os)
                title: hostname
                subtitle: root.peerStatus(online, relay, lastSeen)
                subtitleKind: online ? "success" : "neutral"
                status: exitNode ? "Exit node" : ""
                statusKind: exitNode ? "warning" : "neutral"
                active: online || activeConnection
                actions: [
                    {
                        "id": "copy-dns",
                        "icon": peerRow.copiedAddress === "dns" ? "󰄬" : "󰆏",
                        "label": "DNS",
                        "active": peerRow.copiedAddress === "dns",
                        "enabled": peerRow.dnsName !== ""
                    },
                    {
                        "id": "copy-ip",
                        "icon": peerRow.copiedAddress === "ip" ? "󰄬" : "󰆏",
                        "label": "IP",
                        "active": peerRow.copiedAddress === "ip",
                        "enabled": peerRow.ipv4 !== ""
                    }
                ]
                onActionPressed: actionId => {
                    if (actionId === "copy-dns" && peerRow.dnsName) {
                        Quickshell.clipboardText = peerRow.dnsName
                        peerRow.copiedAddress = "dns"
                        copiedTimer.restart()
                    } else if (actionId === "copy-ip" && peerRow.ipv4) {
                        Quickshell.clipboardText = peerRow.ipv4
                        peerRow.copiedAddress = "ip"
                        copiedTimer.restart()
                    }
                }

                Timer {
                    id: copiedTimer
                    interval: 1400
                    onTriggered: peerRow.copiedAddress = ""
                }
            }
        }

        ApplicationEmptyState {
            visible: peerModel.count === 0
            theme: root.theme
            icon: "󰌘"
            title: root.connected ? "No other devices" : "Mesh is offline"
            message: root.connected
                ? "Devices in this tailnet will appear here."
                : "Reconnect Tailscale to see your devices."
        }

        Text {
            visible: Number(root.status.hiddenPeerCount || 0) > 0
            Layout.fillWidth: true
            text: "+ " + Number(root.status.hiddenPeerCount || 0) + " more devices in the admin console"
            color: root.theme.textMuted
            horizontalAlignment: Text.AlignHCenter
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.microTextSize
            renderType: Text.NativeRendering
        }

        Text {
            visible: root.actionError !== "" || Boolean(root.status.error)
            Layout.fillWidth: true
            text: root.actionError || String(root.status.error || "")
            color: root.theme.critical
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.microTextSize
            renderType: Text.NativeRendering
        }
    }

    Component.onCompleted: root.syncPeerModel()
}
