import QtQuick
import Quickshell
import "Services"
import "Settings"

ShellRoot {
    id: test
    property int step: 0
    property var captured: null
    readonly property string fixture: Qt.resolvedUrl("battery.py").toString().replace("file://", "")
    Theme { id: theme }
    SettingsBattery { id: backend; helper: test.fixture }
    FloatingWindow {
        visible: true; implicitWidth: 640; implicitHeight: 900
        SettingsBatteryHealth { id: controls; theme: theme; backend: backend; width: 500 }
    }
    function check(condition, message) { if (!condition) throw new Error("Step " + step + ": " + message) }
    function find(parent, name) {
        if (parent.objectName === name) return parent
        for (const child of parent.children || []) { const result = find(child, name); if (result) return result }
        return null
    }
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (backend.busy) return
            try {
                switch (test.step++) {
                case 0:
                    test.check(!backend.ready && !backend.active, "Hidden battery view should not poll")
                    backend.active = true
                    break
                case 1:
                    test.check(backend.ready && backend.batteries.length === 2, "Battery list missing")
                    test.check(test.find(controls, "batterySummary_1").text.includes("Unknown"), "Unknown readings turned into numbers")
                    test.check(!test.find(controls, "batteryLimit_1").enabled, "Unsupported control enabled")
                    test.check(controls.limitDescription(backend.batteries[0]).includes("Firmware"), "Firmware limit invented a percentage")
                    test.captured = backend.batteries[0]
                    test.find(controls, "batteryLimit_0").clicked()
                    test.check(backend.busy && !backend.batteries[0].enabled, "Optimistic charge-limit update")
                    backend.active = false
                    break
                case 2:
                    test.check(backend.batteries[0].enabled && !backend.active, "Hidden-window write was not verified")
                    test.find(controls, "batteryLimit_0").clicked()
                    break
                case 3:
                    test.check(backend.error.includes("denied") && backend.batteries[0].enabled, "Denied charge change accepted")
                    backend.batteries = [Object.assign({}, backend.batteries[0], {identity: "replacement"})]
                    backend.setLimit(test.captured, true)
                    test.check(backend.error.includes("changed") && !backend.busy, "Stale battery was retargeted")
                    backend.helper = "/nonexistent/battery-health.py"
                    backend.refresh(true)
                    break
                case 4:
                    test.check(!backend.ready && backend.batteries.length === 0, "Failure retained writable rows")
                    backend.helper = test.fixture
                    backend.refresh(true)
                    break
                case 5:
                    test.check(backend.ready && !backend.error, "Refresh did not recover")
                    backend.batteries = []
                    test.check(test.find(controls, "batteryHealthStatus").text.includes("No system batteries"), "No-battery explanation missing")
                    backend.available = false
                    test.check(test.find(controls, "batteryHealthStatus").text.includes("UPower"), "Missing daemon explanation missing")
                    console.log("SETTINGS_BATTERY_PASSED")
                    Qt.quit()
                }
            } catch (error) { console.error(error); Qt.quit() }
        }
    }
}
