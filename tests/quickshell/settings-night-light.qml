import QtQuick
import Quickshell
import "Services"

ShellRoot {
    id: test
    property int step: 0
    SettingsNightLight { id: backend; helper: Qt.resolvedUrl("night-light.py").toString().replace("file://", "") }
    function check(condition, message) { if (!condition) throw new Error(message) }
    Timer {
        interval: 70
        running: true
        repeat: true
        onTriggered: {
            if (backend.reading || backend.busy) return
            try {
                test.check(!backend.error, backend.error)
                switch (test.step) {
                case 0:
                    test.check(backend.ready && backend.available && !backend.running, "Off discovery failed")
                    backend.apply("always", 4500, "21:00", "07:00")
                    test.step++
                    break
                case 1:
                case 3:
                    if (!backend.running || backend.actualTemperature !== 4500) { backend.refresh(); return }
                    if (test.step === 1) backend.apply("off", 4500, "21:00", "07:00")
                    else backend.apply("always", 3500, "21:00", "07:00")
                    test.step++
                    break
                case 2:
                    if (backend.running || backend.preferences.mode !== "off") { backend.refresh(); return }
                    backend.apply("always", 4500, "21:00", "07:00")
                    test.step++
                    break
                case 4:
                    if (!backend.running || backend.actualTemperature !== 3500) { backend.refresh(); return }
                    backend.apply("schedule", 3000, "22:15", "06:45")
                    test.step++
                    break
                case 5:
                    if (!backend.running || backend.actualTemperature !== 3000) { backend.refresh(); return }
                    backend.apply("off", 3000, "22:15", "06:45")
                    test.step++
                    break
                case 6:
                    if (backend.running || backend.actualTemperature !== -1) { backend.refresh(); return }
                    console.log("SETTINGS_NIGHT_LIGHT_PASSED")
                    Qt.quit()
                }
            } catch(error) { console.error(String(error)); Qt.quit() }
        }
    }
}
