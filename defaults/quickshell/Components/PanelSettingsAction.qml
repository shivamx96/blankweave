import QtQuick
import "PanelSettings.js" as PanelSettings

ControlAction {
    required property string panelKey
    required property var bar
    required property var panel
    readonly property var destination: PanelSettings.destinations[panelKey]
    icon: "󰒓"
    label: destination.label
    onPressed: {
        panel.open = false
        bar.shell.openSettings(destination.id)
    }
}
