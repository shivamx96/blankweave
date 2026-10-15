import QtQuick
import Quickshell
import "Services"
ShellRoot {
    id: root
    property int step: 0
    property string oldRevision: ""
    SettingsTask { id: backend; script: "unused"; helper: Qt.resolvedUrl("task.py").toString().replace("file://", "") }
    function check(value) { if (!value) throw new Error("Task backend step " + step) }
    Timer {
        interval: 150; repeat: true; running: true
        onTriggered: {
            if (backend.busy) return
            try {
                switch (root.step++) {
                case 0: root.check(!backend.ready); backend.active = true; break
                case 1:
                    root.check(backend.writable && !backend.data.value)
                    root.oldRevision = backend.data.revision
                    backend.apply({value: true}); root.check(backend.busy && !backend.data.value); backend.active = false; break
                case 2: root.check(backend.data.value); backend.apply({value: false}, root.oldRevision); break
                case 3: root.check(backend.error.includes("changed") && backend.data.value); backend.helper = "/missing/helper.py"; backend.refresh(true); break
                case 4: root.check(!backend.ready && !backend.writable); console.log("SETTINGS_TASK_PASSED"); Qt.quit()
                }
            } catch (error) { console.error(error); Qt.quit() }
        }
    }
}
