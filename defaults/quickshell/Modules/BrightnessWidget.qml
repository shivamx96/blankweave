import QtQuick
import Quickshell
import "../Components"
import "../Services"

WidgetFrame {
    id: root

    property string percentage: ""
    readonly property string shellDir: Quickshell.env("HOME") + "/.local/share/hyprarch/shell"

    visible: percentage !== ""
    icon: "󰃠"
    label: percentage ? percentage + "%" : ""
    tooltip: percentage ? "Display brightness: " + percentage + "%\nScroll to adjust" : ""

    ScriptPoller {
        id: poller
        command: root.shellDir + "/brightness.sh get"
        interval: 5000
        onUpdated: payload => root.percentage = /^\d+$/.test(payload) ? payload : ""
    }

    Timer {
        id: refreshTimer
        interval: 180
        onTriggered: poller.refresh()
    }

    onScrolled: delta => {
        bar.run([root.shellDir + "/brightness.sh", delta > 0 ? "up" : "down", "2"])
        refreshTimer.restart()
    }
}
