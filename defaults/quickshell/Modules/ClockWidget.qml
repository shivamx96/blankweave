import QtQuick
import Quickshell
import "../Components"

WidgetFrame {
    id: root

    property bool alternate: false

    icon: alternate ? "󰃭" : "󰥔"
    label: alternate
        ? Qt.formatDateTime(clock.date, "ddd, dd MMM")
        : Qt.formatDateTime(clock.date, "hh:mm AP")
    tooltip: Qt.formatDateTime(clock.date, "dddd, d MMMM yyyy\nHH:mm:ss")
    active: alternate
    horizontalPadding: 13

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    onPressed: button => {
        if (button === Qt.LeftButton || button === Qt.RightButton)
            root.alternate = !root.alternate
    }
}
