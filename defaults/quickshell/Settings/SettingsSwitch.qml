import QtQuick
import QtQuick.Controls.Basic

Switch {
    id: root
    required property var theme
    implicitHeight: 36
    implicitWidth: 52 + label.implicitWidth
    spacing: 10
    font.family: theme.fontFamily
    font.pixelSize: theme.smallTextSize
    indicator: Rectangle {
        x: root.leftPadding
        y: (root.height - height) / 2
        width: 36
        height: 20
        radius: 10
        color: root.checked ? root.theme.accentSurface : root.theme.surfaceRaised
        border.color: root.activeFocus ? root.theme.accentBright : root.theme.outline
        opacity: root.enabled ? 1 : 0.55
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
