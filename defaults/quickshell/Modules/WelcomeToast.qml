import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
PanelWindow {
    id: root
    required property var modelData
    required property var theme
    required property var welcome
    screen: modelData
    visible: welcome.visible && (!Hyprland.focusedMonitor || modelData.name === Hyprland.focusedMonitor.name)
    color: "transparent"
    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight
    exclusiveZone: 0
    surfaceFormat.opaque: false
    exclusionMode: ExclusionMode.Ignore
    // Unanchored surfaces are centred, beneath the compositor's session lock.
    WlrLayershell.namespace: "blankweave-welcome"
    WlrLayershell.layer: WlrLayer.Top
    // The empty first-login desktop can accept Enter/Escape immediately.
    // Once an application is active, only a click can focus this surface.
    WlrLayershell.keyboardFocus: welcome.busy ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive
    WelcomeCard {
        id: card
        anchors.fill: parent
        theme: root.theme
        onDismissed: root.welcome.dismiss()
    }
}
