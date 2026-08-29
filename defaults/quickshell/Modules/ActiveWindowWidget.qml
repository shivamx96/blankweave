import QtQuick
import Quickshell.Hyprland
import "../Components"

WidgetFrame {
    id: root

    readonly property var activeWindow: Hyprland.activeToplevel
    readonly property string windowTitle: activeWindow && activeWindow.title
        ? String(activeWindow.title)
        : "Desktop"

    icon: activeWindow ? "󰖯" : "󰇄"
    iconPixelSize: theme.barIconSize + 4
    label: windowTitle.length > 34 ? windowTitle.slice(0, 33) + "…" : windowTitle
    tooltip: activeWindow ? windowTitle : "No active window"
    horizontalPadding: 10
}
