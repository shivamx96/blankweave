import QtQuick
import Quickshell
import Quickshell.Io
import "Services"

ShellRoot {
    id: test
    property int step: 0
    property bool switchDuringRead: false
    readonly property string fixture: Qt.resolvedUrl("brightness.sh").toString().replace("file://", "")
    DisplayBrightness {
        id: backend
        screen: ({name: "eDP-1"})
        helper: test.fixture
        active: false
    }
    Process {
        id: scenario
        onExited: {
            backend.refresh()
            if (test.switchDuringRead) {
                test.switchDuringRead = false
                backend.screen = {name: "eDP-1"}
            }
        }
    }
    function setScenario(name) {
        scenario.command = ["bash", fixture, "scenario", name]
        scenario.running = true
    }
    function check(condition, message) { if (!condition) throw new Error(message) }
    Timer {
        interval: 30
        running: true
        repeat: true
        onTriggered: {
            if (backend.busy || backend.reading || scenario.running) return
            try {
                switch (test.step++) {
                case 0:
                    test.check(!backend.loaded && !backend.available, "Inactive backend polled")
                    backend.active = true
                    break
                case 1:
                    test.check(backend.available && backend.percentage === 60 && backend.backend === "backlight", "Backlight discovery failed")
                    backend.queuePercentage(61)
                    backend.queuePercentage(62)
                    backend.commitPercentage(63)
                    backend.commitPercentage(64)
                    break
                case 2:
                    test.check(backend.percentage === 64 && backend.confirmedPercentage === 64 && !backend.error, "Coalesced apply did not confirm latest value")
                    backend.commitPercentage(0)
                    break
                case 3:
                    test.check(backend.percentage === 5, "Minimum brightness clamp failed")
                    backend.commitPercentage(101)
                    break
                case 4:
                    test.check(backend.percentage === 100, "Maximum brightness clamp failed")
                    test.setScenario("fail-set")
                    break
                case 5:
                    backend.commitPercentage(55)
                    break
                case 6:
                    test.check(backend.percentage === 100 && backend.error.includes("Could not change"), "Failed write was shown as applied")
                    test.setScenario("ignored")
                    break
                case 7:
                    backend.commitPercentage(65)
                    break
                case 8:
                    test.check(backend.percentage === 100 && backend.error.includes("after requesting 65%"), "Successful exit without hardware change was not detected")
                    test.setScenario("normal")
                    break
                case 9:
                    backend.screen = {name: "DP-3"}
                    break
                case 10:
                    test.check(backend.percentage === 40 && backend.backend === "ddc" && !backend.error, "DDC display inherited previous display state")
                    backend.commitPercentage(45)
                    break
                case 11:
                    test.check(backend.percentage === 45 && !backend.error, "DDC change did not verify")
                    test.setScenario("malformed")
                    break
                case 12:
                    test.check(!backend.available && backend.percentage === -1 && backend.error.length > 0, "Malformed status accepted")
                    backend.commitPercentage(50)
                    test.check(!backend.busy, "Unavailable display accepted a write")
                    test.setScenario("wrong-connector")
                    break
                case 13:
                    test.check(!backend.available, "Wrong connector status accepted")
                    test.setScenario("offline")
                    break
                case 14:
                    test.check(!backend.available && backend.error.includes("DDC/CI"), "Unavailable monitor missing guidance")
                    test.setScenario("normal")
                    break
                case 15:
                    test.check(backend.available && backend.percentage === 45, "Refresh did not recover")
                    test.switchDuringRead = true
                    test.setScenario("slow")
                    break
                case 16:
                    test.check(backend.connector === "eDP-1" && backend.percentage === 100, "Late read crossed display selection")
                    test.setScenario("normal")
                    break
                case 17:
                    backend.commitPercentage(70)
                    backend.screen = {name: "DP-3"}
                    break
                case 18:
                    test.check(backend.percentage === 45 && !backend.error, "In-flight write affected the new display")
                    backend.queuePercentage(90)
                    backend.screen = null
                    test.check(!backend.available && !backend.busy, "Disconnect did not cancel pending drag")
                    backend.active = false
                    backend.commitPercentage(95)
                    test.check(!backend.busy, "Inactive backend accepted a write")
                    console.log("SETTINGS_BRIGHTNESS_PASSED")
                    Qt.quit()
                    break
                }
            } catch (error) {
                console.error("SETTINGS_BRIGHTNESS_FAILED: " + error)
                Qt.quit()
            }
        }
    }
}
