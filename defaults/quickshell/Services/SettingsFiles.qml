import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    property bool active: false
    property var files: ({})
    property var overrides: ({})
    readonly property string helper: Qt.resolvedUrl("../../shell/settings-files.py").toString().replace(/^file:\/\//, "")
    onActiveChanged: if (active && !query.running) query.running = true
    function openFolder(file) {
        if (files[file] && files[file].exists)
            Quickshell.execDetached(["python3", helper, "open", file])
    }
    Timer { interval: 3000; running: root.active; repeat: true; onTriggered: if (!query.running) query.running = true }
    Process {
        id: query
        command: ["python3", root.helper, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { const data = JSON.parse(text); root.files = data.files; root.overrides = data.overrides }
                catch (error) { root.files = ({}); root.overrides = ({}) }
            }
        }
    }
}
