import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property var theme
    property string icon: ""
    property string label: ""

    signal pressed

    Layout.fillWidth: true
    Layout.preferredHeight: 30

    RowLayout {
        anchors.centerIn: parent
        spacing: 7

        Text {
            visible: root.icon !== ""
            text: root.icon
            color: root.theme.accentBright
            font.family: root.theme.iconFontFamily
            font.pixelSize: root.theme.iconSize
            renderType: Text.NativeRendering
        }

        Text {
            text: root.label
            color: root.theme.text
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.smallTextSize
            font.weight: Font.Medium
            renderType: Text.NativeRendering
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: actionMouse.containsMouse ? Math.min(root.width - 12, 140) : 0
        height: 1
        color: root.theme.accentBright

        Behavior on width {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        id: actionMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.pressed()
    }
}
