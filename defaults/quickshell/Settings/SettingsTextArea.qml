import QtQuick
import "../Components"
import QtQuick.Controls.Basic

TextArea {
    id: root
    FocusRing { theme: root.theme }
    required property var theme
    padding: root.theme.spacing("xl")
    color: enabled ? theme.text : theme.textMuted
    placeholderTextColor: theme.textMuted
    selectionColor: theme.accentSurface
    selectedTextColor: theme.text
    font.family: theme.fontFamily
    font.weight: theme.textWeight
    font.pixelSize: theme.smallTextSize
    selectByMouse: true
    wrapMode: TextEdit.WrapAnywhere
    textFormat: TextEdit.PlainText
    Keys.onEscapePressed: event => {
        if (text.length) clear()
        else { focus = false; if (parent) parent.forceActiveFocus() }
        event.accepted = true
    }

    background: Rectangle {
        radius: root.theme.widgetRadius
        color: root.theme.surfaceRaised
        border.width: root.activeFocus ? Math.max(1, root.theme.borderWidth) : root.theme.borderWidth
        border.color: root.activeFocus ? root.theme.accentBright : root.theme.outline
        opacity: root.enabled ? 1 : 0.55
    }
}
