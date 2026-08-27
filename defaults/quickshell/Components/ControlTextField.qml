import QtQuick
import QtQuick.Controls

TextField {
    id: root

    required property var theme
    property bool secret: false

    implicitHeight: 32
    leftPadding: 10
    rightPadding: 10
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
        border.width: 1
        border.color: root.activeFocus ? root.theme.accentBright : root.theme.outline

        Behavior on border.color {
            ColorAnimation { duration: 120 }
        }
    }
}
