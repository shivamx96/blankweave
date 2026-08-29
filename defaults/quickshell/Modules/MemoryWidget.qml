import QtQuick
import QtQuick.Layouts
import Quickshell
import "../Components"
import "../Services"

WidgetFrame {
    id: root

    readonly property string shellDir: Quickshell.env("HOME") + "/.local/share/hyprarch/shell"
    readonly property string memoryMark: "memory"
    property var status: ({
        "text": "—",
        "tooltip": "Memory information unavailable",
        "usage": 0,
        "totalBytes": 0,
        "usedBytes": 0,
        "availableBytes": 0,
        "cacheBytes": 0,
        "swapTotalBytes": 0,
        "swapUsedBytes": 0,
        "swapUsage": 0,
        "pressure10": 0,
        "processes": []
    })

    function updateStatus(payload) {
        if (!payload)
            return

        try {
            root.status = JSON.parse(payload)
        } catch (error) {
            root.status = {
                "text": "—",
                "tooltip": "Could not read memory information",
                "usage": 0,
                "processes": []
            }
        }
    }

    function formatBytes(value) {
        const bytes = Number(value || 0)
        if (bytes >= 1073741824)
            return (bytes / 1073741824).toFixed(1) + " GiB"
        if (bytes >= 1048576)
            return (bytes / 1048576).toFixed(0) + " MiB"
        return (bytes / 1024).toFixed(0) + " KiB"
    }

    function processStatus(process) {
        return root.formatBytes(process.rssBytes) + " · "
            + Number(process.usage || 0).toFixed(1) + "%"
    }

    iconMark: root.memoryMark
    iconVisualSize: root.theme.iconSize + 2
    horizontalPadding: 7
    labelWidth: theme.metricLabelWidth
    label: String(status.text ?? "—") + "%"
    active: memoryPanel.open
    attention: Number(status.usage || 0) >= 90 || Number(status.pressure10 || 0) >= 10
    tooltip: String(status.tooltip || "Memory information unavailable") + "\nClick for live details"

    ScriptPoller {
        id: statusPoller
        command: root.shellDir + "/memory-usage.sh"
        interval: memoryPanel.open ? 2000 : 5000
        onUpdated: payload => root.updateStatus(payload)
    }

    onPressed: button => {
        if (button === Qt.LeftButton) {
            root.bar.hideTooltip(root)
            memoryPanel.open = !memoryPanel.open
        }
    }

    ControlPopup {
        id: memoryPanel
        bar: root.bar
        theme: root.theme
        anchorItem: root
        panelWidth: 420

        onOpenChanged: {
            if (open)
                statusPoller.refresh()
        }

        ControlPanelHeader {
            theme: root.theme
            iconMark: root.memoryMark
            title: "MEMORY"
            subtitle: root.formatBytes(root.status.totalBytes) + " usable"
            actions: [
                { "id": "monitor", "icon": "" }
            ]
            onActionPressed: actionId => {
                if (actionId === "monitor") {
                    memoryPanel.open = false
                    root.bar.run(["ghostty", "-e", "btop"])
                }
            }
        }

        ControlDivider { theme: root.theme }

        ApplicationSummary {
            theme: root.theme
            metrics: [
                {
                    "label": "USED",
                    "value": root.formatBytes(root.status.usedBytes),
                    "active": true
                },
                {
                    "label": "AVAILABLE",
                    "value": root.formatBytes(root.status.availableBytes)
                },
                {
                    "label": "TOTAL",
                    "value": root.formatBytes(root.status.totalBytes)
                }
            ]
        }

        TelemetryGauge {
            theme: root.theme
            icon: "󰍛"
            label: "MEMORY UTILIZATION"
            value: Number(root.status.usage || 0)
            valueText: Math.round(Number(root.status.usage || 0)) + "%"
            attention: Number(root.status.usage || 0) >= 90
        }

        ControlSectionLabel {
            theme: root.theme
            text: "ALLOCATION"
        }

        ApplicationSummary {
            theme: root.theme
            metrics: [
                {
                    "label": "CACHE",
                    "value": root.formatBytes(root.status.cacheBytes)
                },
                {
                    "label": "SWAP",
                    "value": Number(root.status.swapTotalBytes || 0) > 0
                        ? root.formatBytes(root.status.swapUsedBytes)
                            + " / " + root.formatBytes(root.status.swapTotalBytes)
                        : "OFF"
                },
                {
                    "label": "PRESSURE 10S",
                    "value": Number(root.status.pressure10 || 0).toFixed(2) + "%",
                    "attention": Number(root.status.pressure10 || 0) >= 10
                }
            ]
        }

        TelemetryGauge {
            visible: Number(root.status.swapTotalBytes || 0) > 0
            theme: root.theme
            icon: "󰓡"
            label: "SWAP UTILIZATION"
            value: Number(root.status.swapUsage || 0)
            valueText: Math.round(Number(root.status.swapUsage || 0)) + "%"
            attention: Number(root.status.swapUsage || 0) >= 75
        }

        ControlDivider { theme: root.theme }

        ControlSectionLabel {
            theme: root.theme
            text: "TOP MEMORY CONSUMERS"
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Repeater {
                model: root.status.processes || []

                ApplicationListRow {
                    required property var modelData

                    theme: root.theme
                    rowHeight: 38
                    icon: "󰘚"
                    title: String(modelData.name || "Process")
                    subtitle: "PID " + String(modelData.pid || "—")
                    status: root.processStatus(modelData)
                    active: Number(modelData.usage || 0) >= 5
                }
            }
        }
    }
}
