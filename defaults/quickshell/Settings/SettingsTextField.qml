import QtQuick
import "../Components"

ControlTextField {
    id: root
    implicitHeight: Math.max(36, contentHeight + topPadding + bottomPadding)
    leftPadding: root.theme.spacing("xl")
    rightPadding: root.theme.spacing("xl")
    font.weight: theme.textWeight
    color: enabled ? theme.text : theme.textMuted
    selectionColor: theme.accentSurface
    selectedTextColor: theme.text
    selectByMouse: true
    background: Rectangle {
        radius: root.theme.widgetRadius
        color: root.theme.surfaceRaised
        border.width: root.activeFocus ? Math.max(1, root.theme.borderWidth) : root.theme.borderWidth
        border.color: root.activeFocus ? root.theme.accentBright : root.theme.outline
        opacity: root.enabled ? 1 : 0.55
    }
}
