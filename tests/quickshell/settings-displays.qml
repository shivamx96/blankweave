import QtQuick
import Quickshell
import Quickshell.Io
import "Services"

ShellRoot {
    id: test
    property int step: 0
    property bool queuePlacement: false
    readonly property string fixture: Qt.resolvedUrl("displays.sh").toString().replace("file://", "")
    SettingsDisplays { id: backend; helper: test.fixture }
    Process {
        id: scenario
        onExited: {
            backend.refresh()
            if (test.queuePlacement) {
                test.queuePlacement = false
                backend.apply("arrangement", 1)
            }
        }
    }
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
                    test.check(!backend.canApply("arrangement"), "Internal monitor can be moved")
                    backend.apply("arrangement", 1)
                    test.check(!backend.busy, "Internal monitor mutation accepted")
                    backend.selectDisplay(1)
                    test.check(backend.canApply("arrangement"), "External monitor cannot be moved")
                    test.check(backend.choices("arrangement").join() === "Automatic,Left,Right,Above,Below", "Wrong position choices")
                    backend.apply("arrangement", 99)
                    test.check(!backend.busy, "Invalid position accepted")
                    backend.apply("arrangement", 1)
                    break
                case 10:
                    test.check(!backend.error && backend.selection("arrangement") === 1, "Position was not refreshed")
                    test.check(backend.monitor.x === -2560 && backend.description("arrangement").includes("-2560"), "Live coordinates missing")
                    test.check(backend.selection("scale") === 3, "Moving changed scale")
                    backend.apply("arrangement", 4)
                    break
                case 11:
                    test.check(backend.error.includes("display position"), "Position failure was not reported")
                    test.check(backend.selection("arrangement") === 4 && backend.monitor.y === 0, "Saved position and live coordinates conflated")
                    backend.apply("arrangement", 0)
                    break
                case 12:
                    test.check(!backend.error && backend.selection("arrangement") === 0, "Automatic placement retry failed")
                    test.check(backend.selection("scale") === 3, "Automatic placement reset scale")
                    test.setScenario("reconnected")
                    break
                case 13:
                    backend.selectDisplay(1)
                    test.check(backend.selectedConnector === "DP-7" && backend.selection("arrangement") === 1, "Reconnected display state missing")
                    test.setScenario("desktop")
                    break
                case 14:
                    test.check(backend.canApply("arrangement"), "Desktop without built-in display cannot be positioned")
                    backend.selectDisplay(1)
                    test.queuePlacement = true
                    test.setScenario("external-only")
                    break
                case 15:
                    test.check(!backend.canApply("arrangement") && backend.error.includes("connected displays changed"), "Queued placement ran after the second display disappeared")
                    test.check(backend.description("arrangement").includes("Connect another"), "Missing single-display explanation")
                    backend.apply("arrangement", 1)
                    test.check(!backend.busy, "Lone external monitor mutation accepted")
                    backend.helper = "/missing/settings-displays.sh"
                    backend.refresh()
                    break
                case 16:
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
