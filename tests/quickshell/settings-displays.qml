import QtQuick
import Quickshell
import Quickshell.Io
import "Services"

ShellRoot {
    id: test
    property int step: 0
    readonly property string fixture: Qt.resolvedUrl("displays.sh").toString().replace("file://", "")
    SettingsDisplays { id: backend; helper: test.fixture }
    Process { id: scenario; onExited: backend.refresh() }
    function setScenario(name) {
        scenario.command = ["bash", fixture, "scenario", name]
        scenario.running = true
    }
    function check(condition, message) { if (!condition) throw new Error(message) }
    Component.onCompleted: backend.refresh()
    Timer {
        interval: 30
        running: true
        repeat: true
        onTriggered: {
            if (backend.busy || backend.reading || scenario.running) return
            try {
                switch (test.step++) {
                case 0:
                    test.check(backend.ready && backend.monitors.length === 2, "Discovery failed")
                    test.check(backend.selectedConnector === "eDP-1", "Initial display missing")
                    backend.selectDisplay(1)
                    test.check(backend.monitor.name === "DP-3", "Selection failed")
                    test.check(backend.choices("scale").join() === "Automatic,100%,125%,150%,200%", "Wrong scale choices")
                    backend.apply("scale", 99)
                    backend.apply("unknown", 0)
                    test.check(!backend.busy, "Invalid action accepted")
                    test.setScenario("reordered")
                    break
                case 1:
                    test.check(backend.selectedConnector === "DP-3", "Reorder changed selected display")
                    backend.refresh()
                    test.check(!backend.busy && backend.reading, "Background refresh disables open controls")
                    backend.apply("scale", 0)
                    test.check(backend.busy, "Apply did not lock controls")
                    backend.selectDisplay(1)
                    test.check(backend.selectedConnector === "DP-3", "Selection changed during apply")
                    backend.apply("scale", 2)
                    break
                case 2:
                    test.check(!backend.error && backend.selection("scale") === 0, "Automatic apply failed")
                    test.check(backend.monitor.effectiveScale === 2 && backend.details.includes("200%"), "Active scale missing")
                    backend.apply("scale", 2)
                    break
                case 3:
                    test.check(backend.operationError.length > 0, "Failed apply not reported")
                    test.check(backend.selection("scale") === 3, "Failed saved preference was shown as active")
                    test.check(backend.savedScaleNotice.includes("125%"), "Pending saved preference missing")
                    test.setScenario("external")
                    break
                case 4:
                    test.check(backend.selection("scale") === 4, "External change not reflected")
                    test.setScenario("unplugged")
                    break
                case 5:
                    test.check(backend.selectedConnector === "eDP-1", "Disconnected selection retained")
                    test.setScenario("empty")
                    break
                case 6:
                    test.check(!backend.ready && backend.monitors.length === 0 && !backend.readError, "Empty state incorrect")
                    backend.apply("scale", 0)
                    test.check(!backend.busy, "Applied without a display")
                    test.setScenario("malformed")
                    break
                case 7:
                    test.check(!backend.ready && backend.readError.length > 0, "Malformed status accepted")
                    test.setScenario("offline")
                    break
                case 8:
                    test.check(!backend.ready && backend.readError.length > 0, "Failed status accepted")
                    test.setScenario("initial")
                    break
                case 9:
                    test.check(backend.ready && !backend.readError, "Refresh did not recover")
                    backend.helper = "/missing/settings-displays.sh"
                    backend.refresh()
                    break
                case 10:
                    test.check(!backend.ready && backend.readError.length > 0, "Missing helper accepted")
                    console.log("SETTINGS_DISPLAYS_PASSED")
                    Qt.quit()
                    break
                }
            } catch (error) {
                console.error("SETTINGS_DISPLAYS_FAILED: " + error)
                Qt.quit()
            }
        }
    }
}
