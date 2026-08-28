import QtQuick
import QtQuick.Layouts
import Quickshell

RowLayout {
    id: root

    required property var theme
    property string label: ""
    property string value: ""
    property string copyText: value
    property bool copied: false

    Layout.fillWidth: true
    Layout.preferredHeight: 25
    spacing: 8

    Text {
        Layout.preferredWidth: 82
        text: root.label
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.microTextSize
        renderType: Text.NativeRendering
    }

    Text {
        Layout.fillWidth: true
        text: root.value || "--"
        color: root.copyText ? root.theme.text : root.theme.textMuted
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideMiddle
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.microTextSize
        font.weight: Font.DemiBold
        renderType: Text.NativeRendering
    }

    Item {
        Layout.preferredWidth: 24
        Layout.preferredHeight: 24
        opacity: root.copyText ? 1 : 0.35

        Text {
            anchors.centerIn: parent
            text: root.copied ? "󰄬" : "󰆏"
            color: root.copied ? root.theme.success : root.theme.textMuted
            font.family: root.theme.iconFontFamily
            font.pixelSize: root.theme.iconSize
            renderType: Text.NativeRendering
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: copyMouse.containsMouse ? 15 : 0
            height: 1
            color: root.theme.accentBright

            Behavior on width { NumberAnimation { duration: 120 } }
        }

        MouseArea {
            id: copyMouse
            anchors.fill: parent
            enabled: root.copyText !== ""
            hoverEnabled: enabled
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                Quickshell.clipboardText = root.copyText
                root.copied = true
                copiedTimer.restart()
            }
        }
    }

    Timer {
        id: copiedTimer
        interval: 1400
        onTriggered: root.copied = false
    }
}
