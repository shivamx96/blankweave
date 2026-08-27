import QtQuick
import Quickshell
import "../Components"

WidgetFrame {
    id: root

    icon: "󰣇"
    iconOnly: true
    active: true
    tooltip: "System overview"
    horizontalPadding: 10

    onPressed: button => {
        if (button === Qt.LeftButton)
            bar.run(["ghostty", "-e", "bash", "-c", "fastfetch; printf '\nPress Enter to close...'; read -r"])
    }
}
