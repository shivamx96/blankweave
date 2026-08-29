import QtQuick
import Quickshell
import Quickshell.Io
import "../Components"
import "../Services"

WidgetFrame {
    id: root

    property int percentage: -1
    property string backend: ""
    property int pendingPercentage: -1
    property int applyingPercentage: -1
    property bool immediatePending: false

    readonly property string shellDir: Quickshell.env("HOME") + "/.local/share/hyprarch/shell"
    readonly property string connector: String(root.bar.screen.name || "")
    readonly property string reportedModel: String(root.bar.screen.model || "")
    readonly property string displayName: reportedModel === "LG HDR 4K"
        ? "LG UltraFine 27UL850"
        : (reportedModel || connector || "Display")
    readonly property string backendName: backend === "ddc" ? "DDC/CI" : "Hardware backlight"

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

    visible: percentage >= 0
    icon: percentage < 34 ? "󰃞" : (percentage < 67 ? "󰃟" : "󰃠")
    iconPixelSize: theme.barIconSize - 2
    label: percentage >= 0 ? percentage + "%" : ""
    tooltip: percentage >= 0
        ? displayName + ": " + percentage + "%\nClick for controls · Scroll to adjust"
        : ""

    ScriptPoller {
        id: poller
        command: root.shellDir + "/brightness.sh status " + root.connector
        interval: 10000
        onUpdated: payload => {
            if (!payload)
                return

            try {
                const status = JSON.parse(payload)
                const next = Number(status.percentage)
                if (Number.isFinite(next) && !brightnessControl.pressed && !applyTimer.running && !applyProcess.running)
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

    onPressed: button => {
        if (button === Qt.LeftButton) {
            root.bar.hideTooltip(root)
            brightnessPanel.open = !brightnessPanel.open
        }
    }

    onScrolled: delta => {
        if (root.percentage >= 0)
            root.queuePercentage(root.percentage + (delta > 0 ? 2 : -2))
    }

    ControlPopup {
        id: brightnessPanel
        bar: root.bar
        theme: root.theme
        anchorItem: root

        ControlPanelHeader {
            theme: root.theme
            icon: "󰃠"
            title: "DISPLAY"
            subtitle: root.displayName + " · " + root.backendName
            actions: [
                { "id": "theme", "icon": root.theme.dark ? "󰖙" : "󰖔" }
            ]
            onActionPressed: actionId => {
                if (actionId === "theme") {
                    brightnessPanel.preserveNextClose = true
                    themeCloseGuard.restart()
                    root.bar.run([root.shellDir + "/theme-toggle.sh"])
                }
            }
        }

        ControlSectionLabel {
            theme: root.theme
            text: "BRIGHTNESS"
        }

        ControlValueRow {
            id: brightnessControl
            theme: root.theme
            from: 5
            to: 100
            value: root.percentage
            stepSize: 1
            valueText: root.percentage + "%"
            onValueMoved: value => root.queuePercentage(value)
            onValueCommitted: value => root.commitPercentage(value)
        }
    }

    Timer {
        id: themeCloseGuard
        interval: 1800
        onTriggered: brightnessPanel.preserveNextClose = false
    }
}
