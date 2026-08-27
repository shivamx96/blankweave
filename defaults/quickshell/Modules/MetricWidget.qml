import QtQuick
import "../Components"
import "../Services"

WidgetFrame {
    id: root

    property string command: ""
    property int interval: 5000
    property string clickCommand: ""
    property string value: "—"
    property string detail: ""
    property string suffix: "%"

    label: value + suffix
    tooltip: detail

    ScriptPoller {
        id: poller
        command: root.command
        interval: root.interval
        onUpdated: payload => {
            if (!payload)
                return

            try {
                const parsed = JSON.parse(payload)
                root.value = String(parsed.text ?? "—")
                root.detail = String(parsed.tooltip ?? "")
            } catch (error) {
                root.value = payload
                root.detail = payload
            }
        }
    }

    onPressed: button => {
        if (button === Qt.LeftButton && root.clickCommand)
            bar.run(["bash", "-lc", root.clickCommand])
    }
}
