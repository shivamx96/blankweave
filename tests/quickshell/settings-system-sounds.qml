import QtQuick
import Quickshell
import "Services"

ShellRoot {
    id: test
    property int step: 0
    readonly property string fixture: Qt.resolvedUrl("sounds.py").toString().replace("file://", "")
    SettingsSystemSounds { id: backend; active: true; helper: test.fixture }
    function check(condition, message) { if (!condition) throw new Error(message) }
    Timer {
        interval: 70; running: true; repeat: true
        onTriggered: {
            if (backend.busy) return
            try {
                switch (test.step++) {
                case 0:
                    test.check(backend.ready && backend.canPreview && !backend.gtkSynced, "Initial sound status missing")
                    backend.apply("event-sounds", false)
                    break
                case 1:
                    test.check(!backend.preferences["event-sounds"] && !backend.canPreview, "Mute not confirmed")
                    backend.apply("event-sounds", true)
                    break
                case 2:
                    test.check(backend.canPreview, "Preview unavailable after enable")
                    backend.apply("theme-name", "custom")
                    break
                case 3:
                    test.check(backend.error.includes("Fixture") && backend.preferences["theme-name"] === "freedesktop", "Failed theme was accepted")
                    backend.preview()
                    break
                case 4:
                    test.check(backend.error.includes("playback"), "Preview failure missing")
                    backend.helper = "/nonexistent/sound-settings.py"
                    backend.refresh(true)
                    break
                case 5:
                    test.check(!backend.ready && !backend.canPreview, "Missing backend left writes enabled")
                    backend.helper = test.fixture
                    backend.refresh(true)
                    break
                case 6:
                    test.check(backend.ready && !backend.error, "Refresh did not recover")
                    backend.sync()
                    break
                default:
                    test.check(backend.gtkSynced && !backend.error, "GTK sync not confirmed")
                    console.log("SETTINGS_SYSTEM_SOUNDS_PASSED")
                    Qt.quit()
                }
            } catch (error) { console.error(error); Qt.quit() }
        }
    }
}
