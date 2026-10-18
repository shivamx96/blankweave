import QtQuick
import QtQuick.Controls.Basic

ScrollBar {
    id: root
    required property var theme
    policy: ScrollBar.AsNeeded
    visible: policy === ScrollBar.AlwaysOn || (policy === ScrollBar.AsNeeded && size < 1)
    padding: 2
    implicitWidth: 10
    minimumSize: 0.05
    contentItem: Rectangle {
        implicitWidth: 6
        implicitHeight: 6
        radius: 3
        color: root.pressed ? root.theme.accentBright : root.theme.textMuted
        opacity: root.active ? 0.8 : 0.4
    }
    background: Rectangle { color: "transparent" }
}
