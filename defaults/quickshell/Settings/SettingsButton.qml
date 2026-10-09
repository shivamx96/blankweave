import QtQuick
import QtQuick.Controls

Button {
    id: root
    required property var theme
    property bool selected: false

    implicitHeight: 36
    implicitWidth: label.implicitWidth + 28
    hoverEnabled: true
    font.family: theme.fontFamily
    font.pixelSize: theme.textSize
    Accessible.name: text

    contentItem: Text {
        id: label
        text: root.text
        font: root.font
        color: !root.enabled ? root.theme.textMuted
            : root.selected ? root.theme.accentBright : root.theme.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Rectangle {
        radius: root.theme.widgetRadius
        color: root.down ? root.theme.surfacePressed
            : root.selected ? root.theme.accentSurface
            : root.hovered ? root.theme.surfaceHover : root.theme.surfaceRaised
        border.width: 1
        border.color: root.activeFocus ? root.theme.accentBright : root.theme.outline
        opacity: root.enabled ? 1 : 0.55
    }
}
