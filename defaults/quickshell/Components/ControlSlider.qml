import QtQuick
import QtQuick.Controls

Slider {
    id: root

    required property var theme

    implicitHeight: 28
    hoverEnabled: true

    background: Item {
        x: root.leftPadding
        y: root.topPadding + root.availableHeight / 2 - 1
        implicitWidth: 180
        implicitHeight: 2
        width: root.availableWidth
        height: implicitHeight

        Rectangle {
            anchors.fill: parent
            color: root.theme.divider
        }

        Rectangle {
            width: root.visualPosition * parent.width
            height: parent.height
            color: root.theme.accent
        }
    }

    handle: Item {
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: root.topPadding + root.availableHeight / 2 - height / 2
        implicitWidth: 10
        implicitHeight: 14

        Rectangle {
            anchors.centerIn: parent
            width: root.pressed ? 3 : 2
            height: 12
            color: root.theme.accentBright

            Rectangle {
                anchors.centerIn: parent
                width: 7
                height: parent.height + 4
                color: root.theme.accent
                opacity: root.hovered ? 0.18 : 0.08
            }

            Behavior on width {
                NumberAnimation { duration: 100 }
            }
        }
    }
}
