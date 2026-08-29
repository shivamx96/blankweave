import QtQuick
import QtQuick.Layouts
import Quickshell
import "../Components"
import "../Services"

WidgetFrame {
    id: root

    readonly property string shellDir: Quickshell.env("HOME") + "/.local/share/blankweave/shell"
    property var systemInfo: ({
        "available": false,
        "hostname": "",
        "os": "",
        "error": ""
    })

    function updateSystemInfo(payload) {
        if (!payload)
            return
        try {
            root.systemInfo = JSON.parse(payload)
        } catch (error) {
            root.systemInfo = {
                "available": false,
                "error": "Could not read system information"
            }
        }
    }

    function formatDuration(seconds) {
        const totalMinutes = Math.max(0, Math.floor(Number(seconds || 0) / 60))
        const days = Math.floor(totalMinutes / 1440)
        const hours = Math.floor((totalMinutes % 1440) / 60)
        const minutes = totalMinutes % 60
        if (days > 0)
            return days + "d " + hours + "h"
        if (hours > 0)
            return hours + "h " + minutes + "m"
        return minutes + "m"
    }

    function compactBytes(bytes) {
        const value = Math.max(0, Number(bytes || 0))
        if (value <= 0)
            return "—"
        const gibibytes = value / Math.pow(1024, 3)
        if (gibibytes >= 1024)
            return (gibibytes / 1024).toFixed(1) + "T"
        return gibibytes.toFixed(gibibytes >= 100 ? 0 : 1) + "G"
    }

    function usagePair(used, total) {
        return root.compactBytes(used) + " / " + root.compactBytes(total)
    }

    function openFastfetch() {
        systemPanel.open = false
        root.bar.run([
            "ghostty", "-e", "bash", "-c",
            "fastfetch; printf '\\nPress Enter to close...'; read -r"
        ])
    }

    iconMark: "blankweave"
    iconOnly: true
    active: systemPanel.open
    tooltip: "System overview\nRight-click: full terminal report"
    horizontalPadding: 10

    onPressed: button => {
        if (button === Qt.LeftButton) {
            root.bar.hideTooltip(root)
            systemPanel.open = !systemPanel.open
            if (systemPanel.open)
                systemPoller.refresh()
        }
        else if (button === Qt.RightButton) {
            root.openFastfetch()
        }
    }

    ScriptPoller {
        id: systemPoller
        command: root.shellDir + "/system-overview.sh"
        interval: systemPanel.open ? 30000 : 120000
        onUpdated: payload => root.updateSystemInfo(payload)
    }

    ControlPopup {
        id: systemPanel
        bar: root.bar
        theme: root.theme
        anchorItem: root
        panelWidth: 420

        ControlPanelHeader {
            theme: root.theme
            iconMark: "blankweave"
            title: "SYSTEM OVERVIEW"
            subtitle: root.systemInfo.available
                ? String(root.systemInfo.hostname || "System") + " · " + String(root.systemInfo.os || "Linux")
                : "Blankweave machine snapshot"
            actions: [
                { "id": "refresh", "icon": "󰑐" },
                { "id": "report", "icon": "󰋊" }
            ]
            onActionPressed: actionId => {
                if (actionId === "refresh")
                    systemPoller.refresh()
                else if (actionId === "report")
                    root.openFastfetch()
            }
        }

        ControlDivider { theme: root.theme }

        ApplicationSummary {
            visible: Boolean(root.systemInfo.available)
            theme: root.theme
            metrics: [
                {
                    "label": "UPTIME",
                    "value": root.formatDuration(root.systemInfo.uptimeSeconds),
                    "active": true
                },
                {
                    "label": "MEMORY",
                    "value": root.usagePair(root.systemInfo.memoryUsed, root.systemInfo.memoryTotal)
                },
                {
                    "label": "STORAGE",
                    "value": root.usagePair(root.systemInfo.diskUsed, root.systemInfo.diskTotal)
                }
            ]
        }

        ControlSectionLabel {
            visible: Boolean(root.systemInfo.available)
            theme: root.theme
            text: "HARDWARE"
        }

        ApplicationListRow {
            visible: Boolean(root.systemInfo.available)
            theme: root.theme
            rowHeight: 44
            icon: "󰻠"
            title: String(root.systemInfo.cpu || "Processor")
            subtitle: Number(root.systemInfo.physicalCores || 0) + " cores · "
                + Number(root.systemInfo.logicalCores || 0) + " threads"
        }

        ApplicationListRow {
            visible: Boolean(root.systemInfo.available)
            theme: root.theme
            rowHeight: 44
            icon: "󰢮"
            title: String(root.systemInfo.gpu || "Graphics")
            subtitle: "Graphics adapters"
        }

        ApplicationListRow {
            visible: Boolean(root.systemInfo.available)
            theme: root.theme
            rowHeight: 44
            icon: "󰍛"
            title: String(root.systemInfo.memorySpec
                || (root.compactBytes(root.systemInfo.memoryTotal) + " installed"))
            subtitle: String(root.systemInfo.memoryDetails
                || "DIMM details require a privileged inventory refresh")
        }

        ApplicationListRow {
            visible: Boolean(root.systemInfo.available)
            theme: root.theme
            rowHeight: 44
            icon: "󰌢"
            title: String(root.systemInfo.motherboardName || "Motherboard")
            subtitle: String(root.systemInfo.motherboardVendor || "System board")
        }

        ApplicationListRow {
            visible: Boolean(root.systemInfo.available)
            theme: root.theme
            rowHeight: 44
            icon: "󰍹"
            title: String(root.systemInfo.displayModel || "Display")
            subtitle: String(root.systemInfo.displayDetails || "No active display")
        }

        ControlSectionLabel {
            visible: Boolean(root.systemInfo.available)
            theme: root.theme
            text: "SOFTWARE"
        }

        ApplicationListRow {
            visible: Boolean(root.systemInfo.available)
            theme: root.theme
            rowHeight: 44
            icon: "󰣇"
            title: String(root.systemInfo.os || "Linux") + " · " + String(root.systemInfo.kernel || "")
            subtitle: Number(root.systemInfo.packages || 0) + " packages · "
                + String(root.systemInfo.architecture || "") + " · "
                + String(root.systemInfo.session || "Hyprland · Wayland")
        }

        ApplicationEmptyState {
            visible: !Boolean(root.systemInfo.available)
            theme: root.theme
            icon: "󰋊"
            title: systemPoller.running ? "Reading system information…" : "System overview unavailable"
            message: systemPoller.running ? "" : String(root.systemInfo.error || "Try refreshing the panel.")
        }
    }
}
