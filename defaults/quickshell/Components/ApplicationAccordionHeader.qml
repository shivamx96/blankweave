import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property var theme
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property string badge: ""
    property bool expanded: false
    property bool active: false

    signal pressed

    implicitHeight: 44
    Layout.fillWidth: true
    Layout.preferredHeight: implicitHeight

    Rectangle {
        anchors.fill: parent
        color: headerMouse.containsMouse ? root.theme.accentSurface : "transparent"

        Behavior on color { ColorAnimation { duration: 120 } }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        height: root.expanded ? 26 : 14
        color: root.active ? root.theme.accentBright : root.theme.divider

        Behavior on height { NumberAnimation { duration: 140 } }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 6
        spacing: 9

        Text {
            visible: root.icon !== ""
            Layout.preferredWidth: 20
            horizontalAlignment: Text.AlignHCenter
            text: root.icon
            color: root.active ? root.theme.accentBright : root.theme.textMuted
            font.family: root.theme.iconFontFamily
            font.pixelSize: root.theme.controlIconSize
            renderType: Text.NativeRendering
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
                Layout.fillWidth: true
                text: root.title
                color: root.theme.text
                elide: Text.ElideRight
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.smallTextSize
                font.weight: Font.DemiBold
                renderType: Text.NativeRendering
            }

            Text {
                visible: root.subtitle !== ""
                Layout.fillWidth: true
                text: root.subtitle
                color: root.theme.textMuted
                elide: Text.ElideRight
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.microTextSize
                renderType: Text.NativeRendering
            }
        }

        Text {
            visible: root.badge !== ""
            text: root.badge
            color: root.active ? root.theme.success : root.theme.textMuted
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.microTextSize
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
        }

        Text {
            text: root.expanded ? "󰅀" : "󰅂"
            color: headerMouse.containsMouse ? root.theme.accentBright : root.theme.textMuted
            font.family: root.theme.iconFontFamily
            font.pixelSize: root.theme.iconSize
            renderType: Text.NativeRendering
        }
    }

    MouseArea {
        id: headerMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.pressed()
    }
}
