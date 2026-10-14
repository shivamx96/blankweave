import QtQuick
import Quickshell
import "Services"
import "Settings"
import "."
ShellRoot {
    id: test
    property int step: 0
    property var originalTarget: null
    readonly property string fixture: Qt.resolvedUrl("pointer.py").toString().replace("file://", "")
    Theme { id: theme }
    SettingsPointer { id: backend; helper: test.fixture }
    FloatingWindow {
        visible: true; implicitWidth: 640; implicitHeight: 700
        SettingsPointerControls { id: controls; theme: theme; backend: backend; width: 580 }
    }
    function check(condition, message) { if (!condition) throw new Error("Step " + step + ": " + message) }
    function find(parent, name) {
        if (parent.objectName === name) return parent
        for (const child of parent.children || []) { const result = find(child, name); if (result) return result }
        return null
    }
    Timer {
        interval: 150; running: true; repeat: true
        onTriggered: {
            if (backend.busy) return
            try {
                switch (test.step++) {
                case 0:
                    test.check(!backend.ready && !backend.active, "Hidden pointer view polled")
                    backend.active = true
                    break
                case 1:
                    test.check(backend.ready && controls.writable, "Controls unavailable")
                    test.find(controls, "pointer_sensitivity").activated(5)
                    test.check(backend.busy && backend.values.global.sensitivity === 0, "Optimistic pointer value")
                    backend.active = false
                    break
                case 2:
                    test.check(backend.values.global.sensitivity === 0.25 && !backend.active, "Hidden write not verified")
                    test.originalTarget = Object.assign({}, backend.devices[0], {scope: "device"})
                    controls.target = test.originalTarget
                    break
                case 3:
                    test.check(test.find(controls, "pointer_tap_to_click").currentIndex === 0, "Absent override presented as effective hardware state")
                    test.find(controls, "pointer_tap_to_click").activated(1)
                    break
                case 4:
                    test.check(backend.saved.devices["fixture-touchpad"].tap_to_click === false, "Wrong device or key changed")
                    test.find(controls, "pointer_tap_to_click").activated(2)
                    break
                case 5:
                    test.check(backend.error.includes("overrides") && backend.saved.devices["fixture-touchpad"].tap_to_click === false, "Failed write accepted")
                    test.find(controls, "pointer_sensitivity").popup.open()
                    break
                case 6:
                    backend.devices = [{name: "fixture-touchpad", address: "0xNEW", kind: "touchpad", unique: true}]
                    test.find(controls, "pointer_sensitivity").activated(5)
                    test.check(backend.error.includes("changed") && !backend.busy && !controls.writable, "Open menu retargeted replacement device")
                    test.find(controls, "pointer_sensitivity").popup.close()
                    controls.target = {scope: "global", label: "Pointer defaults"}
                    controls.width = 350
                    backend.helper = "/nonexistent/pointer.py"
                    backend.refresh(true)
                    break
                case 7:
                    test.check(!backend.ready && backend.devices.length === 0 && !controls.writable, "Read failure kept stale writable values")
                    backend.helper = test.fixture
                    backend.refresh(true)
                    break
                case 8:
                    test.check(backend.ready && !backend.error, "Retry did not recover")
                    backend.installed = false
                    test.check(!controls.writable, "Missing integration accepted writes")
                    backend.installed = true
                    backend.synced = false
                    test.check(!controls.writable, "Unloaded saved config accepted writes")
                    console.log("SETTINGS_POINTER_PASSED")
                    Qt.quit()
                }
            } catch (error) { console.error(error); Qt.quit() }
        }
    }
}
