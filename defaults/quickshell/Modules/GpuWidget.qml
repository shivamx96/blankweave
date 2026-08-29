import QtQuick
import QtQuick.Layouts
import Quickshell
import "../Components"
import "../Services"

WidgetFrame {
    id: root

    readonly property string shellDir: Quickshell.env("HOME") + "/.local/share/hyprarch/shell"
    readonly property string gpuMark: "gpu"
    property bool detailLoading: false
    property var status: ({
        "available": false,
        "detailed": false,
        "text": "—",
        "tooltip": "GPU telemetry unavailable",
        "backend": "none",
        "vendor": "",
        "name": "Graphics processor",
        "driver": "",
        "accuracy": "unavailable",
        "usage": 0,
        "memoryUsage": null,
        "temperature": null,
        "memoryUsedBytes": 0,
        "memoryTotalBytes": 0,
        "powerDrawWatts": null,
        "powerLimitWatts": null,
        "clockMHz": null,
        "maxClockMHz": null,
        "fanPercent": null,
        "performanceState": "",
        "idlePercent": null,
        "engines": [],
        "processes": []
    })

    function updateStatus(payload) {
        if (!payload)
            return

        try {
            const parsed = JSON.parse(payload)
            const cachedProcesses = root.status.processes || []
            if (!Boolean(parsed.detailed) && cachedProcesses.length > 0)
                parsed.processes = cachedProcesses
            if (Boolean(parsed.detailed))
                root.detailLoading = false
            root.status = parsed
        } catch (error) {
            root.detailLoading = false
            root.status = {
                "available": false,
                "detailed": false,
                "text": "—",
                "tooltip": "Could not read GPU information",
                "backend": "none",
                "usage": 0,
                "engines": [],
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

    function formatClock(value) {
        const frequency = Number(value || 0)
        return frequency > 0 ? Math.round(frequency) + " MHz" : "—"
    }

    function processStatus(process) {
        const memory = root.formatBytes(process.memoryBytes)
        return process.usage === null || process.usage === undefined
            ? memory
            : Number(process.usage || 0).toFixed(1) + "% · " + memory
    }

    function advancedMonitorCommand() {
        return root.status.backend === "intel"
            ? ["ghostty", "-e", "intel_gpu_top"]
            : ["ghostty", "-e", "nvtop"]
    }

    visible: Boolean(status.available)
    iconMark: root.gpuMark
    horizontalPadding: 7
    labelWidth: theme.metricLabelWidth
    label: String(status.text ?? "—") + "%"
    active: gpuPanel.open
    attention: Number(status.temperature || 0) >= 85
    tooltip: String(status.tooltip || "GPU telemetry unavailable") + "\nClick for live details"

    ScriptPoller {
        id: statusPoller
        command: root.shellDir + "/gpu-usage.sh " + (gpuPanel.open ? "detail" : "summary")
        interval: gpuPanel.open ? 2500 : 5000
        onUpdated: payload => root.updateStatus(payload)
    }

    onPressed: button => {
        if (button === Qt.LeftButton) {
            root.bar.hideTooltip(root)
            gpuPanel.open = !gpuPanel.open
        }
    }

    ControlPopup {
        id: gpuPanel
        bar: root.bar
        theme: root.theme
        anchorItem: root
        panelWidth: 440

        onOpenChanged: {
            if (open) {
                root.detailLoading = true
                statusPoller.refresh()
            } else {
                root.detailLoading = false
            }
        }

        ControlPanelHeader {
            theme: root.theme
            iconMark: root.gpuMark
            title: "GRAPHICS"
            subtitle: String(root.status.name || "Graphics processor")
            actions: [
                { "id": "monitor", "icon": "" }
            ]
            onActionPressed: actionId => {
                if (actionId === "monitor") {
                    gpuPanel.open = false
                    root.bar.run(root.advancedMonitorCommand())
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
                    "label": root.status.temperature === null || root.status.temperature === undefined
                        ? "IDLE"
                        : "TEMPERATURE",
                    "value": root.status.temperature === null || root.status.temperature === undefined
                        ? (root.status.idlePercent === null || root.status.idlePercent === undefined
                            ? "—"
                            : Math.round(Number(root.status.idlePercent)) + "%")
                        : Math.round(Number(root.status.temperature)) + "°C",
                    "attention": Number(root.status.temperature || 0) >= 85
                },
                {
                    "label": "CLOCK",
                    "value": root.formatClock(root.status.clockMHz)
                }
            ]
        }

        TelemetryGauge {
            theme: root.theme
            icon: "󰓅"
            label: root.status.accuracy === "frequency-estimate"
                ? "ACTIVITY ESTIMATE"
                : "GPU UTILIZATION"
            value: Number(root.status.usage || 0)
            valueText: Math.round(Number(root.status.usage || 0)) + "%"
            attention: Number(root.status.usage || 0) >= 95
        }

        TelemetryGauge {
            visible: Number(root.status.memoryTotalBytes || 0) > 0
            theme: root.theme
            icon: "󰘚"
            label: "VRAM UTILIZATION"
            value: Number(root.status.memoryUsedBytes || 0)
            maximum: Number(root.status.memoryTotalBytes || 1)
            valueText: root.formatBytes(root.status.memoryUsedBytes)
                + " / " + root.formatBytes(root.status.memoryTotalBytes)
            attention: Number(root.status.memoryUsedBytes || 0)
                >= Number(root.status.memoryTotalBytes || 1) * 0.9
        }

        TelemetryGauge {
            visible: root.status.powerDrawWatts !== null
                && root.status.powerDrawWatts !== undefined
                && Number(root.status.powerLimitWatts || 0) > 0
            theme: root.theme
            icon: "󰚥"
            label: "BOARD POWER"
            value: Number(root.status.powerDrawWatts || 0)
            maximum: Number(root.status.powerLimitWatts || 1)
            valueText: Number(root.status.powerDrawWatts || 0).toFixed(0) + " W"
            attention: Number(root.status.powerDrawWatts || 0)
                >= Number(root.status.powerLimitWatts || 1) * 0.95
        }

        ControlSectionLabel {
            visible: root.status.backend === "intel" && (root.status.engines || []).length > 0
            theme: root.theme
            text: "ENGINE ACTIVITY"
        }

        ColumnLayout {
            visible: root.status.backend === "intel" && (root.status.engines || []).length > 0
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: root.status.engines || []

                TelemetryGauge {
                    required property var modelData

                    theme: root.theme
                    label: String(modelData.name || "Engine").toUpperCase()
                    value: Number(modelData.usage || 0)
                    valueText: Number(modelData.usage || 0).toFixed(1) + "%"
                    segments: 16
                }
            }
        }

        ControlDivider { theme: root.theme }

        ApplicationSummary {
            theme: root.theme
            metrics: [
                {
                    "label": Number(root.status.memoryTotalBytes || 0) > 0
                        ? "VRAM"
                        : "GPU RESIDENT",
                    "value": root.formatBytes(root.status.memoryUsedBytes)
                },
                {
                    "label": root.status.backend === "intel" ? "TELEMETRY" : "POWER STATE",
                    "value": root.status.backend === "intel"
                        ? (root.status.accuracy === "live" ? "ENGINE BUSY" : "ESTIMATE")
                        : String(root.status.performanceState || "—")
                },
                {
                    "label": "DRIVER",
                    "value": String(root.status.driver || "—")
                }
            ]
        }

        ControlSectionLabel {
            theme: root.theme
            text: "ACTIVE GPU CLIENTS"
        }

        ColumnLayout {
            visible: (root.status.processes || []).length > 0
            Layout.fillWidth: true
            spacing: 0

            Repeater {
                model: root.status.processes || []

                ApplicationListRow {
                    required property var modelData

                    theme: root.theme
                    rowHeight: 38
                    icon: "󰘚"
                    title: String(modelData.name || "GPU client")
                    subtitle: "PID " + String(modelData.pid || "—")
                    status: root.processStatus(modelData)
                    active: Number(modelData.usage || 0) >= 10
                }
            }
        }

        ApplicationEmptyState {
            visible: (root.status.processes || []).length === 0
            theme: root.theme
            icon: "󰾲"
            title: root.detailLoading ? "Reading GPU clients…" : "No active GPU clients"
            message: root.detailLoading
                ? "Collecting current engine and memory activity."
                : (root.status.backend === "intel" && root.status.accuracy !== "live"
                    ? "Client details require Intel engine telemetry access."
                    : "GPU workloads will appear here when active.")
        }
    }
}
