import QtQuick
import "../Components"

ControlTextField {
    id: root
    implicitHeight: 36
    leftPadding: 12
    rightPadding: 12
    color: enabled ? theme.text : theme.textMuted
    selectionColor: theme.accentSurface
    selectedTextColor: theme.text
    selectByMouse: true
    background: Rectangle {
        radius: root.theme.widgetRadius
        color: root.theme.surfaceRaised
        border.color: root.activeFocus ? root.theme.accentBright : root.theme.outline
        opacity: root.enabled ? 1 : 0.55
    }
}
