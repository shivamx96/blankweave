import QtQuick
import "../Components"

WidgetFrame {
    id: root

    icon: "󰕰"
    iconOnly: true
    active: Boolean(root.bar.shell.launcherOpen)
    tooltip: "Applications\nRight-click: Fuzzel fallback"
    horizontalPadding: 8

    onPressed: button => {
        if (button === Qt.LeftButton) {
            root.bar.hideTooltip(root)
            root.bar.shell.toggleLauncher()
        }
        else if (button === Qt.RightButton) {
            root.bar.run(["fuzzel"])
        }
    }
}
