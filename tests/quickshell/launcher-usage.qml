import QtQuick
import Quickshell
import "Services"
ShellRoot {
    id: test
    property int phase: 0
    LauncherUsage {
        id: usage
        entries: [{id:"terminal"}, {id:"browser"}]
    }
    Timer {
        interval: 150; running: true; repeat: true
        onTriggered: {
            try {
                if (!usage.ready) return
                if (test.phase === 0) {
                    if (Object.keys(usage.history).length !== Number(Quickshell.env("USAGE_EXISTING") || 0)) throw new Error("Missing/corrupt state must be empty")
                    usage.record("terminal")
                    test.phase++
                } else {
                    if (usage.writeError) throw new Error(usage.writeError)
                    if (usage.history.terminal.count !== Number(Quickshell.env("USAGE_EXISTING") || 0) + 1) throw new Error("Recorded count")
                    console.log("USAGE_PASSED")
                    Qt.quit()
                }
            } catch (error) { console.error(error); Qt.quit() }
        }
    }
}
