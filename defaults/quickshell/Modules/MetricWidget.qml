import QtQuick
import "../Components"
import "../Services"

WidgetFrame {
    id: root
    dataSources: [poller]

    property string command: ""
    property int interval: 5000
    property string clickCommand: ""
    property string value: "—"
    property string detail: ""
    property string suffix: "%"

    horizontalPadding: 7
    labelWidth: theme.metricLabelWidth
    label: value + suffix
    tooltip: detail

    SharedPoller {
        id: poller
        service: root.bar.shell.pollers
        key: "metric:" + root.command
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
                // ScriptPoller rejects malformed output and retains the last value.
            }
        }
    }

    onPressed: button => {
        if (button === Qt.LeftButton && root.clickCommand)
            bar.run(["bash", "-lc", root.clickCommand])
    }
}
