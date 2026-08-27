import QtQuick
import "../Components"
import "../Services"

WidgetFrame {
    id: root

    required property string processName
    required property string displayName
    property string clickCommand: ""
    property bool running: false

    visible: running
    iconOnly: true
    active: true
    tooltip: displayName + " is running"

    ScriptPoller {
        command: "pgrep -x -- " + root.processName + " >/dev/null && printf running || printf stopped"
        interval: 5000
        onUpdated: payload => root.running = payload === "running"
    }

    onPressed: button => {
        if (button === Qt.LeftButton && root.clickCommand)
            bar.run(["bash", "-lc", root.clickCommand])
    }
}
