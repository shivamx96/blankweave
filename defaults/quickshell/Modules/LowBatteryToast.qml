import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: root
    required property var modelData
    required property var theme
    required property var power
    readonly property var warning: power.lowBattery
    readonly property bool focusedScreen: !Hyprland.focusedMonitor
        || modelData.name === Hyprland.focusedMonitor.name

    screen: modelData
    visible: warning.warningLevel > 0 && focusedScreen
    color: "transparent"
    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight
    exclusiveZone: 0
    surfaceFormat.opaque: false
    anchors.bottom: true
    margins.bottom: theme.spacing("page")
    WlrLayershell.namespace: "blankweave-low-battery"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    LowBatteryCard {
        id: card
        anchors.fill: parent
        theme: root.theme
        power: root.power
    }
}
