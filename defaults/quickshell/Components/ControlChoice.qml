import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property var theme
    property string text: ""
    property bool selected: false
    property bool busy: false
    // An optional colour sample drawn before the label, for choices that are
    // about a colour (a theme) rather than a word (a position).
    property var swatch: null

    signal pressed

    implicitWidth: content.implicitWidth + root.theme.spacing("section")
    implicitHeight: Math.max(28, content.implicitHeight + root.theme.spacing("xs") * 2)
    Layout.preferredHeight: implicitHeight
    opacity: enabled ? 1 : 0.45

    Rectangle {
        anchors.fill: parent
        color: root.selected ? root.theme.accentSurface : "transparent"
        border.width: root.selected || choiceMouse.containsMouse ? root.theme.borderWidth : 0
        border.color: root.selected ? root.theme.accentBright : root.theme.outlineStrong
    }

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: root.theme.spacing("sm")

        Rectangle {
            visible: root.swatch !== null && !root.busy
            Layout.preferredWidth: 8
            Layout.preferredHeight: 8
            radius: height / 2
            color: root.swatch !== null ? root.swatch : "transparent"
            border.width: root.theme.borderWidth
            border.color: root.theme.outlineStrong
        }

        Text {
            id: label
            text: root.busy ? "Applying…" : root.text
            color: root.selected ? root.theme.accentBright : root.theme.text
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.microTextSize
            font.weight: root.selected ? Font.DemiBold : Font.Normal
            renderType: Text.NativeRendering
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: root.selected || choiceMouse.containsMouse ? Math.max(12, root.width - 12) : 0
        height: 1
        color: root.theme.accentBright

        Behavior on width {
            NumberAnimation { duration: Math.round(root.theme.motionDuration * 140 / 150); easing.type: root.theme.motionEasing }
        }
    }

    MouseArea {
        id: choiceMouse
        anchors.fill: parent
        enabled: root.enabled && !root.busy
        hoverEnabled: enabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.pressed()
    }
}
