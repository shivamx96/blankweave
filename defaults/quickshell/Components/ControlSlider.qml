import QtQuick
import "PanelNavigation.js" as Navigation
import QtQuick.Controls.Basic

Slider {
    id: root
    Keys.onPressed: event => {
        if (Navigation.route(root, event)) return
        if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space].includes(event.key)) { pressed = true; event.accepted = true }
    }
    Keys.onReleased: event => {
        if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space].includes(event.key)) { pressed = false; event.accepted = true }
    }
    FocusRing { theme: root.theme }

    required property var theme

    // High contrast replaces the theme palette: its outlineStrong equals text,
    // so use a mid-grey track to retain a visible filled/unfilled boundary.
    readonly property color trackColor: root.theme.sliderTrack || root.theme.outlineStrong

    readonly property color fillColor: root.theme.accent

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
            color: root.trackColor
        }

        Rectangle {
            width: root.visualPosition * parent.width
            height: parent.height
            color: root.fillColor
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
            color: root.fillColor

            Rectangle {
                anchors.centerIn: parent
                width: 7
                height: parent.height + 4
                color: root.fillColor
                opacity: root.hovered ? 0.18 : 0.08
            }

            Behavior on width {
                NumberAnimation { duration: Math.round(root.theme.motionDuration * 100 / 150) }
            }
        }
    }
}
