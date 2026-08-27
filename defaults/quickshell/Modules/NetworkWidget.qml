import QtQuick
import Quickshell
import "../Components"
import "../Services"

WidgetFrame {
    id: root

    property string statusIcon: "󰤭"
    property string statusText: "Offline"
    property string statusTooltip: "No network connection"
    readonly property string script: Quickshell.env("HOME") + "/.local/share/hyprarch/shell/network-status.sh"

    icon: statusIcon
    label: statusText
    tooltip: statusTooltip
    attention: statusText === "Offline"

    ScriptPoller {
        command: root.script
        interval: 3000
        onUpdated: payload => {
            if (!payload)
                return

            try {
                const parsed = JSON.parse(payload)
                root.statusIcon = String(parsed.icon || "󰤭")
                root.statusText = String(parsed.text || "Offline")
                root.statusTooltip = String(parsed.tooltip || "")
            } catch (error) {
                root.statusText = "Offline"
                root.statusTooltip = payload
            }
        }
    }

    onPressed: button => {
        if (button === Qt.LeftButton)
            bar.run(["ghostty", "-e", "nmtui"])
    }
}
