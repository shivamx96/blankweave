import QtQuick
import "PanelNavigation.js" as Navigation
import QtQuick.Controls.Basic

TextField {
    id: root
    Keys.onPressed: event => Navigation.route(root, event)
    FocusRing { theme: root.theme }

    required property var theme
    property bool panelTextInput: true
    property bool secret: false
    Accessible.name: placeholderText

    implicitHeight: Math.max(32, contentHeight + topPadding + bottomPadding)
    leftPadding: root.theme.spacing("lg")
    rightPadding: root.theme.spacing("lg")
    color: theme.text
    placeholderTextColor: theme.textMuted
    selectionColor: theme.accentBright
    selectedTextColor: theme.surfaceRaised
    echoMode: secret ? TextInput.Password : TextInput.Normal
    font.family: theme.fontFamily
    font.pixelSize: theme.smallTextSize
    renderType: Text.NativeRendering

    // A Keys handler declared on an instance runs in addition to this one, not
    // instead of it, so a field that needs different Escape behaviour sets
    // escapeHandler rather than declaring a second handler.
    property var escapeHandler: null
    Keys.onEscapePressed: event => {
        if (escapeHandler) escapeHandler()
        else if (text.length) { clear(); textEdited() }
        else if (Navigation.panel(root)) { event.accepted = false; return }
        else { focus = false; if (parent) parent.forceActiveFocus() }
        event.accepted = true
    }

    background: Rectangle {
        color: root.activeFocus ? root.theme.accentSurface : "transparent"
        border.width: root.activeFocus ? Math.max(1, root.theme.borderWidth) : root.theme.borderWidth
        border.color: root.activeFocus ? root.theme.accentBright : root.theme.outline

        Behavior on border.color {
            ColorAnimation { duration: Math.round(root.theme.motionDuration * 120 / 150) }
        }
    }
}
