import QtQuick
import QtQuick.Controls.Basic

TextArea {
    id: root
    required property var theme
    padding: 12
    color: enabled ? theme.text : theme.textMuted
    placeholderTextColor: theme.textMuted
    selectionColor: theme.accentSurface
    selectedTextColor: theme.text
    font.family: theme.fontFamily
    font.pixelSize: theme.smallTextSize
    selectByMouse: true
    wrapMode: TextEdit.WrapAnywhere
    textFormat: TextEdit.PlainText
    background: Rectangle {
        radius: root.theme.widgetRadius
        color: root.theme.surfaceRaised
        border.color: root.activeFocus ? root.theme.accentBright : root.theme.outline
        opacity: root.enabled ? 1 : 0.55
    }
}
