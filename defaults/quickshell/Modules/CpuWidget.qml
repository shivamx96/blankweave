import QtQuick
import QtQuick.Layouts
import Quickshell
import "../Components"
import "../Services"

WidgetFrame {
    id: root

    readonly property string shellDir: Quickshell.env("HOME") + "/.local/share/hyprarch/shell"
    property var status: ({
        "text": "—",
        "tooltip": "CPU information unavailable",
        "model": "Processor",
        "usage": 0,
        "temperature": null,
        "frequencyGhz": 0,
        "physicalCores": 0,
        "logicalCpus": 0,
        "load1": 0,
        "load5": 0,
        "load15": 0,
        "uptime": "—",
        "cores": [],
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
                "tooltip": "Could not read CPU information",
                "model": "Processor",
                "usage": 0,
                "cores": [],
                "processes": []
            }
        }
    }

    function processStatus(process) {
        return Number(process.usage || 0).toFixed(1) + "% CPU · "
            + Number(process.memory || 0).toFixed(1) + "% RAM"
    }

    icon: ""
    horizontalPadding: 7
    labelWidth: theme.metricLabelWidth
    label: String(status.text ?? "—") + "%"
    active: cpuPanel.open
    attention: Number(status.temperature || 0) >= 90
    tooltip: String(status.tooltip || "CPU information unavailable") + "\nClick for live details"

    ScriptPoller {
        id: statusPoller
        command: root.shellDir + "/cpu-usage.sh"
        interval: cpuPanel.open ? 1500 : 5000
        onUpdated: payload => root.updateStatus(payload)
    }

    onPressed: button => {
        if (button === Qt.LeftButton) {
            root.bar.hideTooltip(root)
            cpuPanel.open = !cpuPanel.open
        }
    }

    ControlPopup {
        id: cpuPanel
        bar: root.bar
        theme: root.theme
        anchorItem: root
        panelWidth: 430

        onOpenChanged: {
            if (open)
                statusPoller.refresh()
        }

        ControlPanelHeader {
            theme: root.theme
            icon: ""
            title: "PROCESSOR"
            subtitle: String(root.status.model || "Processor")
            actions: [
                { "id": "monitor", "icon": "󰍛" }
            ]
            onActionPressed: actionId => {
                if (actionId === "monitor") {
                    cpuPanel.open = false
                    root.bar.run(["ghostty", "-e", "btop"])
                }
            }
        }

        ControlDivider { theme: root.theme }

        ApplicationSummary {
            theme: root.theme
            metrics: [
                {
                    "label": "USAGE",
                    "value": Math.round(Number(root.status.usage || 0)) + "%",
                    "active": true
                },
                {
                    "label": "TEMPERATURE",
                    "value": root.status.temperature === null || root.status.temperature === undefined
                        ? "—"
                        : Math.round(Number(root.status.temperature)) + "°C",
                    "attention": Number(root.status.temperature || 0) >= 90
                },
                {
                    "label": "FREQUENCY",
                    "value": Number(root.status.frequencyGhz || 0).toFixed(2) + " GHz"
                }
            ]
        }

        TelemetryGauge {
            theme: root.theme
            icon: "󰓅"
            label: "TOTAL UTILIZATION"
            value: Number(root.status.usage || 0)
            valueText: Math.round(Number(root.status.usage || 0)) + "%"
            attention: Number(root.status.usage || 0) >= 90
        }

        ControlSectionLabel {
            theme: root.theme
            text: "CORE ACTIVITY · " + Number(root.status.physicalCores || 0)
                + " CORES · " + Number(root.status.logicalCpus || 0) + " THREADS"
        }

        GridLayout {
            id: coreGrid
            Layout.fillWidth: true
            columns: 4
            columnSpacing: 12
            rowSpacing: 6

            Repeater {
                model: root.status.cores || []

                Item {
                    id: coreCell

                    required property int index
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.preferredHeight: 20

                    Text {
                        id: coreLabel
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        text: String(coreCell.index + 1).padStart(2, "0")
                        color: root.theme.textMuted
                        font.family: root.theme.monoFontFamily
                        font.pixelSize: root.theme.microTextSize
                        renderType: Text.NativeRendering
                    }

                    Rectangle {
                        anchors.left: coreLabel.right
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 4
                        color: root.theme.outline
                        opacity: 0.55

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width * Math.max(0, Math.min(1, Number(coreCell.modelData || 0) / 100))
                            color: Number(coreCell.modelData || 0) >= 90
                                ? root.theme.critical
                                : root.theme.accentBright

                            Behavior on width {
                                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                }
            }
        }

        ControlDivider { theme: root.theme }

        ApplicationSummary {
            theme: root.theme
            metrics: [
                { "label": "LOAD 1M", "value": Number(root.status.load1 || 0).toFixed(2) },
                { "label": "LOAD 5M", "value": Number(root.status.load5 || 0).toFixed(2) },
                { "label": "UPTIME", "value": String(root.status.uptime || "—") }
            ]
        }

        ControlSectionLabel {
            theme: root.theme
            text: "TOP CPU CONSUMERS"
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
                    active: Number(modelData.usage || 0) > 10
                }
            }
        }
    }
}
