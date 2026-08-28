import QtQuick
import Quickshell.Io

Item {
    id: root

    property string command: ""
    property int interval: 5000
    property string output: ""
    property bool ready: false
    property bool refreshPending: false
    readonly property bool running: process.running

    signal updated(string payload)

    visible: false
    implicitWidth: 0
    implicitHeight: 0

    function refresh() {
        if (!root.command)
            return
        if (process.running) {
            root.refreshPending = true
            return
        }

        root.refreshPending = false
        process.command = ["bash", "-lc", root.command]
        process.running = true
    }

    Process {
        id: process

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.output = String(text || "").trim()
                root.ready = true
                root.updated(root.output)
            }
        }

        onExited: {
            if (root.refreshPending)
                Qt.callLater(root.refresh)
        }
    }

    Timer {
        interval: Math.max(250, root.interval)
        running: root.interval > 0
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()
}
