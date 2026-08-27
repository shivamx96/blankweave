import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property var bar
    required property var theme

    property string icon: ""
    property string label: ""
    property string tooltip: ""
    property bool active: false
    property bool attention: false
    property bool iconOnly: false
    property int labelWeight: Font.Medium
    property int horizontalPadding: theme.widgetPadding
    property color foreground: attention ? theme.critical : (active ? theme.accentBright : theme.text)

    signal pressed(int button)
    signal scrolled(real delta)

    implicitWidth: content.implicitWidth + horizontalPadding * 2
    implicitHeight: theme.widgetHeight
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: root.label ? 6 : 0

        Text {
            visible: root.icon !== ""
            text: root.icon
            color: root.foreground
            font.family: theme.iconFontFamily
            font.pixelSize: theme.iconSize
            renderType: Text.NativeRendering
        }

        Text {
            visible: !root.iconOnly && root.label !== ""
            text: root.label
            color: root.foreground
            font.family: theme.fontFamily
            font.pixelSize: theme.textSize
            font.weight: root.labelWeight
            font.letterSpacing: 0.1
            renderType: Text.NativeRendering
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: mouse.containsMouse ? Math.max(8, root.width - root.horizontalPadding * 2) : 0
        height: 1
        color: root.attention ? root.theme.critical : root.theme.accentBright
        opacity: mouse.pressed ? 1 : 0.72

        Behavior on width {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onEntered: {
            if (root.tooltip)
                root.bar.showTooltip(root, root.tooltip)
        }
        onExited: root.bar.hideTooltip(root)
        onClicked: mouse => root.pressed(mouse.button)
        onWheel: wheel => root.scrolled(wheel.angleDelta.y)
    }

    Component.onDestruction: root.bar.hideTooltip(root)
}
