import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property var theme
    property string icon: ""
    property string label: ""
    property bool active: false
    property bool attention: false

    signal pressed

    Layout.fillWidth: true
    Layout.preferredHeight: 30
    opacity: enabled ? 1 : 0.45

    RowLayout {
        anchors.centerIn: parent
        spacing: 7

        Text {
            visible: root.icon !== ""
            text: root.icon
            color: root.attention
                ? root.theme.critical
                : (root.active ? root.theme.accentBright : root.theme.text)
            font.family: root.theme.iconFontFamily
            font.pixelSize: root.theme.iconSize
            renderType: Text.NativeRendering
        }

        Text {
            text: root.label
            color: root.attention ? root.theme.critical : root.theme.text
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.smallTextSize
            font.weight: Font.Medium
            renderType: Text.NativeRendering
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: root.active || actionMouse.containsMouse ? Math.min(root.width - 12, 140) : 0
        height: 1
        color: root.attention ? root.theme.critical : root.theme.accentBright

        Behavior on width {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        id: actionMouse
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: enabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.pressed()
    }
}
