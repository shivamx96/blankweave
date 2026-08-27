import QtQuick
import Quickshell
import "../Components"

WidgetFrame {
    id: root

    readonly property string script: Quickshell.env("HOME") + "/.local/share/hyprarch/shell/power-menu.sh"

    icon: "󰐥"
    iconOnly: true
    tooltip: "Power menu"
    horizontalPadding: 10

    onPressed: button => {
        if (button === Qt.LeftButton)
            bar.run([root.script])
    }
}
