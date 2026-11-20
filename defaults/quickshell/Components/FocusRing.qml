import QtQuick
import "PanelNavigation.js" as Navigation

// An inset two-pixel outline plus corner marks: focus changes shape as well as colour.
Item {
    id: root
    required property var theme
    property Item target: parent
    readonly property var panel: Navigation.panel(target)
    anchors.fill: parent
    z: 100
    visible: target.activeFocus && (panel ? panel.keyboardMode : target.activeFocus)
    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        color: "transparent"
        border.width: 2
        border.color: (root.theme.focusIndicator || root.theme.text)
    }
    Rectangle { x: 0; y: 0; width: 7; height: 4; color: (root.theme.focusIndicator || root.theme.text) }
    Rectangle { x: parent.width - width; y: parent.height - height; width: 7; height: 4; color: (root.theme.focusIndicator || root.theme.text) }
}
