import QtQuick
import QtQuick.Controls.Basic

TextField {
    id: root

    required property var theme
    property bool secret: false

    implicitHeight: Math.max(32, contentHeight + topPadding + bottomPadding)
    leftPadding: root.theme.spacing("lg")
    rightPadding: root.theme.spacing("lg")
    color: theme.text
    placeholderTextColor: theme.textMuted
    selectionColor: theme.accent
    selectedTextColor: theme.surfaceRaised
    echoMode: secret ? TextInput.Password : TextInput.Normal
    font.family: theme.fontFamily
    font.pixelSize: theme.smallTextSize
    renderType: Text.NativeRendering

    background: Rectangle {
        color: root.activeFocus ? root.theme.accentSurface : "transparent"
        border.width: root.activeFocus ? Math.max(1, root.theme.borderWidth) : root.theme.borderWidth
        border.color: root.activeFocus ? root.theme.accentBright : root.theme.outline

        Behavior on border.color {
            ColorAnimation { duration: Math.round(root.theme.motionDuration * 120 / 150) }
        }
    }
}
