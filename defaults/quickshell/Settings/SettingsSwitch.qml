import QtQuick
import "../Components/PanelNavigation.js" as Navigation
import "../Components"
import QtQuick.Controls.Basic

Switch {
    id: root
    property bool keyPressed: false
    readonly property bool controlDown: down || keyPressed
    Accessible.pressed: pressed || keyPressed
    onActiveFocusChanged: if (!activeFocus) keyPressed = false
    Keys.onPressed: event => {
        if (Navigation.route(root, event)) return
        if ([Qt.Key_Return, Qt.Key_Enter].includes(event.key)) {
            if (!event.isAutoRepeat) keyPressed = true
            event.accepted = true
        }
    }
    Keys.onReleased: event => {
        if ([Qt.Key_Return, Qt.Key_Enter].includes(event.key)) {
            const activate = keyPressed && enabled
            keyPressed = false
            if (activate && !event.isAutoRepeat) { toggle(); toggled(); clicked() }
            event.accepted = true
        }
    }
    FocusRing { theme: root.theme }
    required property var theme
    property bool pending: false
    implicitHeight: Math.max(36, implicitContentHeight + topPadding + bottomPadding)
    implicitWidth: 52 + label.implicitWidth
    spacing: root.theme.spacing("lg")
    font.family: theme.fontFamily
    font.weight: theme.textWeight
    font.pixelSize: theme.smallTextSize
    indicator: Rectangle {
        x: root.leftPadding
        y: (root.height - height) / 2
        width: 36
        height: 20
        radius: 10
        color: root.controlDown ? root.theme.surfacePressed : root.checked ? root.theme.accentSurface : root.theme.surfaceRaised
        border.width: root.activeFocus ? Math.max(1, root.theme.borderWidth) : root.theme.borderWidth
        border.color: root.activeFocus ? root.theme.accentBright : root.theme.outline
        opacity: root.pending ? 0.65 : root.enabled ? 1 : 0.55
        Rectangle {
            x: root.checked ? 18 : 4
            y: 4
            width: 12
            height: 12
            radius: 6
            color: root.checked ? root.theme.accentBright : root.theme.textMuted
        }
    }
    contentItem: Text {
        id: label
        leftPadding: 46
        text: root.text
        textFormat: Text.PlainText
        font: root.font
        verticalAlignment: Text.AlignVCenter
        color: root.enabled ? root.theme.text : root.theme.textMuted
    }
}
