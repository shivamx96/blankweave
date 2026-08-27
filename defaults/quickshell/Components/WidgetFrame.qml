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
    property int horizontalPadding: theme.widgetPadding
    property color foreground: attention ? theme.critical : (active ? theme.accentBright : theme.text)

    signal pressed(int button)
    signal scrolled(real delta)

    implicitWidth: content.implicitWidth + horizontalPadding * 2
    implicitHeight: theme.widgetHeight
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight

    Rectangle {
        anchors.fill: parent
        radius: theme.widgetRadius
        color: mouse.pressed
            ? theme.surfacePressed
            : (mouse.containsMouse ? theme.surfaceHover : (root.active ? theme.accentSurface : "transparent"))
        border.width: root.active ? 1 : 0
        border.color: root.attention ? theme.critical : theme.outlineStrong

        Behavior on color {
            ColorAnimation { duration: 120 }
        }
    }

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: root.label ? 6 : 0

        Text {
            visible: root.icon !== ""
            text: root.icon
            color: root.foreground
            font.family: theme.iconFontFamily
            font.pixelSize: 15
            renderType: Text.NativeRendering
        }

        Text {
            visible: !root.iconOnly && root.label !== ""
            text: root.label
            color: root.foreground
            font.family: theme.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
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
