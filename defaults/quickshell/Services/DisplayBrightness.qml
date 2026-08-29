import QtQuick
import Quickshell
import Quickshell.Io

// Brightness state for one screen. The bar entry owns one of these for the
// screen it lives on and keeps it polling; the display panel instantiates one
// per other screen and polls those only while it is open, so a closed bar
// never spends DDC/CI round-trips on displays it is not showing.
Item {
    id: root

    required property var screen
    property bool active: true
    property int interval: 10000
    // Set by the slider that edits this display while it is being dragged,
    // so a poll that lands mid-drag cannot snap the handle back.
    property bool held: false

    readonly property string shellDir: Quickshell.env("HOME") + "/.local/share/hyprarch/shell"
    readonly property string connector: String((screen && screen.name) || "")
    readonly property string reportedModel: String((screen && screen.model) || "")
    // The laptop panel is the anchor external displays are placed against,
    // so it is named for its role rather than its EDID model.
    readonly property bool internal: /^(eDP|LVDS|DSI)-/.test(connector)
    readonly property string displayName: internal
        ? "Built-in display"
        : (reportedModel === "LG HDR 4K"
            ? "LG UltraFine 27UL850"
            : (reportedModel || connector || "Display"))
    readonly property string backendName: backend === "ddc" ? "DDC/CI" : "Hardware backlight"
    readonly property bool available: percentage >= 0

    property int percentage: -1
    property string backend: ""
    property int pendingPercentage: -1
    property int applyingPercentage: -1
    property bool immediatePending: false

    visible: false
    implicitWidth: 0
    implicitHeight: 0

    function queuePercentage(value) {
        const next = Math.max(5, Math.min(100, Math.round(value)))
        root.percentage = next
        root.pendingPercentage = next
        root.immediatePending = false
        applyTimer.restart()
    }

    function commitPercentage(value) {
        const next = Math.max(5, Math.min(100, Math.round(value)))
        root.percentage = next
        root.pendingPercentage = next
        root.immediatePending = true
        applyTimer.stop()
        root.applyPending()
    }

    function applyPending() {
        if (root.pendingPercentage < 0 || applyProcess.running)
            return

        root.applyingPercentage = root.pendingPercentage
        root.immediatePending = false
        applyProcess.command = [
            root.shellDir + "/brightness.sh",
            "set",
            String(root.applyingPercentage),
            root.connector
        ]
        applyProcess.running = true
    }

    function refresh() {
        poller.refresh()
    }

    onActiveChanged: {
        if (active)
            poller.refresh()
    }

    ScriptPoller {
        id: poller
        // An empty command makes refresh() a no-op, so an inactive display is
        // never read, not even by the poller's initial refresh.
        command: root.active ? root.shellDir + "/brightness.sh status " + root.connector : ""
        interval: root.active ? root.interval : 0
        onUpdated: payload => {
            if (!payload)
                return

            try {
                const status = JSON.parse(payload)
                const next = Number(status.percentage)
                if (Number.isFinite(next) && !root.held && !applyTimer.running && !applyProcess.running)
                    root.percentage = Math.round(next)
                root.backend = String(status.backend || "")
            } catch (error) {
                root.percentage = -1
                root.backend = ""
            }
        }
    }

    Timer {
        id: applyTimer
        interval: root.backend === "ddc" ? 100 : 30
        onTriggered: root.applyPending()
    }

    Process {
        id: applyProcess

        onExited: {
            if (root.pendingPercentage !== root.applyingPercentage) {
                if (root.immediatePending)
                    Qt.callLater(root.applyPending)
                else
                    applyTimer.restart()
            }
            else {
                root.immediatePending = false
                settleTimer.restart()
            }
        }
    }

    Timer {
        id: settleTimer
        interval: root.backend === "ddc" ? 900 : 300
        onTriggered: poller.refresh()
    }
}
