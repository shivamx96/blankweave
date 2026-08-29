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
        "loggedIn": false,
        "needsLogin": false,
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
    property bool loginUrlOpened: false
    property bool logoutArmed: false
    readonly property bool running: Boolean(status.daemonRunning)
    readonly property bool connected: Boolean(status.connected)
    readonly property bool loggedIn: Boolean(status.loggedIn)
    readonly property bool busy: actionProcess.running
    readonly property string tailscaleMark: "tailscale-" + (connected ? "connected" : "disconnected")

    function updateStatus(payload) {
        if (!payload)
            return
        try {
            root.status = JSON.parse(payload)
            if (!root.status.loggedIn)
                root.logoutArmed = false
            root.syncPeerModel()
        } catch (error) {
            root.status = {
                "available": true,
                "daemonRunning": true,
                "connected": false,
                "loggedIn": false,
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

    function handleActionEvent(payload) {
        const line = String(payload || "").trim()
        if (!line)
            return
        const separator = line.indexOf("\t")
        const event = separator >= 0 ? line.slice(0, separator) : line
        const value = separator >= 0 ? line.slice(separator + 1).trim() : ""

        if (event === "auth-url" && value.startsWith("https://") && !root.loginUrlOpened) {
            root.loginUrlOpened = true
            root.actionOutput = "Complete sign-in in your browser"
            root.bar.run(["xdg-open", value])
        } else if (event === "error") {
            root.actionError = value || "Tailscale authentication failed"
        } else if (event === "state") {
            root.actionOutput = value
            statusPoller.refresh()
        }
    }

    function beginAction(kind) {
        if (actionProcess.running)
            return
        root.actionKind = kind
        root.actionOutput = ""
        root.actionError = ""
        root.loginUrlOpened = false
        actionProcess.command = [
            root.shellDir + "/tailscale-auth.sh",
            kind,
            Quickshell.env("USER")
        ]
        actionProcess.running = true
    }

    function beginConnectionAction(connect) {
        if (connect && !root.loggedIn)
            root.beginAction("login")
        else
            root.beginAction(connect ? "connect" : "disconnect")
    }

    function requestLogout() {
        if (root.logoutArmed) {
            logoutGuard.stop()
            root.logoutArmed = false
            root.beginAction("logout")
        } else {
            root.logoutArmed = true
            logoutGuard.restart()
        }
    }

    visible: running
    iconMark: root.tailscaleMark
    iconOnly: true
    active: tailscalePanel.open
    attention: running && !connected
    tooltip: !loggedIn
        ? "Tailscale sign-in required\nClick to authenticate"
        : (connected
        ? "Tailscale connected · " + Number(status.onlinePeerCount || 0) + " peers online\nClick for mesh controls"
        : "Tailscale " + String(status.backend || "stopped") + "\nClick for controls")

    ScriptPoller {
        id: statusPoller
        command: root.shellDir + "/tailscale-status.sh"
        interval: root.actionKind === "login" ? 1000 : (tailscalePanel.open ? 4000 : 10000)
        onUpdated: payload => root.updateStatus(payload)
    }

    ListModel {
        id: peerModel
    }

    Process {
        id: actionProcess

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root.handleActionEvent(data)
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
            if (exitCode !== 0 && !root.actionError) {
                root.actionError = root.actionKind === "login" && root.loginUrlOpened
                    ? "Sign-in was not completed"
                    : (root.actionOutput || (root.actionKind === "login"
                        ? "Could not start Tailscale sign-in"
                        : "Tailscale action failed"))
            }
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

    Timer {
        id: logoutGuard
        interval: 3500
        onTriggered: root.logoutArmed = false
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
            if (!open && root.logoutArmed) {
                logoutGuard.stop()
                root.logoutArmed = false
            }
        }

        ControlPanelHeader {
            theme: root.theme
            iconMark: root.tailscaleMark
            title: "TAILSCALE"
            subtitle: root.logoutArmed
                ? "Select sign out again to confirm"
                : (!root.loggedIn
                ? (root.actionKind === "login" ? "Waiting for browser sign-in…" : "Sign in required")
                : (root.connected
                ? (String(root.status.tailnet || "Connected") + " · " + String(root.status.hostname || "This device"))
                : (root.busy
                    ? (root.actionKind === "connect" ? "Connecting…" : "Disconnecting…")
                    : String(root.status.backend || "Stopped"))))
            actions: root.loggedIn
                ? [
                    { "id": "admin", "icon": "󰖟" },
                    {
                        "id": "power",
                        "icon": root.connected ? "󰅖" : "󰐥",
                        "active": root.connected
                    },
                    {
                        "id": "logout",
                        "icon": "󰍃",
                        "attention": root.logoutArmed
                    }
                ]
                : [
                    { "id": "login", "icon": "󰍂", "attention": true }
                ]
            onActionPressed: actionId => {
                if (actionId === "admin") {
                    tailscalePanel.open = false
                    root.bar.run(["xdg-open", "https://login.tailscale.com/admin/machines"])
                } else if (actionId === "power") {
                    root.beginConnectionAction(!root.connected)
                } else if (actionId === "login") {
                    root.beginAction("login")
                } else if (actionId === "logout") {
                    root.requestLogout()
                }
            }
        }

        ControlDivider { theme: root.theme }

        ApplicationSummary {
            theme: root.theme
            metrics: [
                {
                    "label": "STATUS",
                    "value": !root.loggedIn ? "Sign in" : (root.connected ? "Online" : "Offline"),
                    "active": root.connected,
                    "attention": !root.loggedIn
                },
                {
                    "label": "PEERS",
                    "value": root.connected
                        ? Number(root.status.onlinePeerCount || 0) + " / " + Number(root.status.peerCount || 0)
                        : "—"
                },
                {
                    "label": "RELAY",
                    "value": root.connected
                        ? String(root.status.relay || "Direct").toUpperCase()
                        : "—"
                }
            ]
        }

        ControlSectionLabel {
            visible: root.loggedIn
            theme: root.theme
            text: "THIS DEVICE"
        }

        ColumnLayout {
            visible: root.loggedIn
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

        ControlDivider { visible: root.loggedIn; theme: root.theme }

        ControlSectionLabel {
            visible: root.loggedIn
            theme: root.theme
            text: "DEVICES"
        }

        ListView {
            id: peerList
            visible: root.loggedIn && peerModel.count > 0
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
            visible: !root.loggedIn || peerModel.count === 0
            theme: root.theme
            icon: root.loggedIn ? "󰌘" : "󰍂"
            title: !root.loggedIn
                ? "Sign in to Tailscale"
                : (root.connected ? "No other devices" : "Mesh is offline")
            message: !root.loggedIn
                ? "Authenticate this device to join your tailnet."
                : (root.connected
                    ? "Devices in this tailnet will appear here."
                    : "Reconnect Tailscale to see your devices.")
        }

        ControlAction {
            visible: !root.loggedIn
            theme: root.theme
            icon: root.actionKind === "login" ? "󰔟" : "󰍂"
            label: root.actionKind === "login"
                ? (root.loginUrlOpened ? "Complete sign-in in browser" : "Starting sign-in…")
                : "Sign in"
            active: root.actionKind === "login"
            enabled: !root.busy
            onPressed: root.beginAction("login")
        }

        Text {
            visible: root.loggedIn && Number(root.status.hiddenPeerCount || 0) > 0
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
