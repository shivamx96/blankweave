import QtQuick
import Quickshell
import "Services"
import "Settings"
import "."
ShellRoot {
    id: test
    property int step: 0
    readonly property string fixture: Qt.resolvedUrl("idle.py").toString().replace("file://", "")
    Theme { id: theme }
    SettingsIdle { id: backend; helper: test.fixture }
    FloatingWindow {
        visible: true; implicitWidth: 640; implicitHeight: 600
        SettingsIdleControls { theme: theme; backend: backend; width: 500 }
    }
    function check(condition, message) { if (!condition) throw new Error("Step " + step + ": " + message) }
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (backend.busy) return
            try {
                switch (test.step++) {
                case 0:
                    test.check(!backend.ready && !backend.active, "Hidden view polled")
                    backend.active = true
                    break
                case 1:
                    test.check(backend.ready && backend.settings.ac.screen === 600, "Initial state missing")
                    backend.apply("ac", "screen", 900)
                    test.check(backend.busy && backend.settings.ac.screen === 600, "Optimistic state")
                    backend.active = false
                    break
                case 2:
                    test.check(backend.settings.ac.screen === 900 && !backend.applied, "Hidden write not verified or pending shown as applied")
                    test.check(backend.settings.battery.screen === 360, "Wrong source edited")
                    backend.apply("battery", "screen", 60)
                    break
                case 3:
                    test.check(backend.error.includes("changed elsewhere") && backend.settings.battery.screen === 360, "Failed edit accepted")
                    backend.helper = "/nonexistent/idle.py"
                    backend.refresh(true)
                    break
                case 4:
                    test.check(!backend.ready && backend.error, "Missing helper retained writable state")
                    backend.helper = test.fixture
                    backend.refresh(true)
                    break
                case 5:
                    test.check(backend.ready && !backend.error, "Retry did not recover")
                    console.log("SETTINGS_IDLE_PASSED")
                    Qt.quit()
                }
            } catch (error) { console.error(error); Qt.quit() }
        }
    }
}
