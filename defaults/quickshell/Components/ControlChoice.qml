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

    implicitWidth: content.implicitWidth + 14
    implicitHeight: 28
    Layout.preferredHeight: implicitHeight
    opacity: enabled ? 1 : 0.45

    Rectangle {
        anchors.fill: parent
        color: root.selected ? root.theme.accentSurface : "transparent"
        border.width: root.selected || choiceMouse.containsMouse ? 1 : 0
        border.color: root.selected ? root.theme.accentBright : root.theme.outlineStrong
    }

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: 6

        Rectangle {
            visible: root.swatch !== null && !root.busy
            Layout.preferredWidth: 8
            Layout.preferredHeight: 8
            radius: 4
            color: root.swatch !== null ? root.swatch : "transparent"
            border.width: 1
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
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
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
