import QtQuick
import Quickshell
import "Services"

ShellRoot {
    id: test
    property int step: 0
    readonly property string fixture: Qt.resolvedUrl("theme.sh").toString().replace("file://", "")
    property QtObject desktopTheme: QtObject {
        property string themeId: "obsidian"
        property string mode: "dark"
    }
    property QtObject preferences: QtObject {
        property bool ready: true
        property string writeError: ""
        property QtObject bar: QtObject {
            property string position: "top"
            property string visibilityMode: "always"
        }
    }
    SettingsAppearance {
        id: backend
        theme: test.desktopTheme
        preferences: test.preferences
        helper: test.fixture
        systemHelper: test.fixture
    }
    function check(condition, message) {
        if (!condition) throw new Error(message)
    }
    Component.onCompleted: backend.refresh()
    Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: {
            if (backend.busy) return
            try {
                switch (test.step++) {
                case 0:
                    test.check(backend.ready && !backend.error, "Backend did not initialize")
                    test.check(backend.themes.length === 2 && backend.systemPending, "Invalid discovery result")
                    test.desktopTheme.themeId = "moss"
                    test.check(backend.selection("theme") === 1, "External theme change not reflected")
                    backend.apply("bar-position", 1)
                    test.check(test.preferences.bar.position === "bottom", "Bar did not use shared preferences")
                    backend.apply("bar-visibility", 2)
                    test.check(test.preferences.bar.visibilityMode === "auto-hide", "Visibility mapping failed")
                    backend.apply("bar-position", 99)
                    test.check(test.preferences.bar.position === "bottom", "Invalid value accepted")
                    test.preferences.ready = false
                    backend.apply("bar-position", 0)
                    test.check(test.preferences.bar.position === "bottom", "Wrote before preferences were ready")
                    test.preferences.ready = true
                    backend.apply("theme", 1)
                    break
                case 1:
                    test.check(!backend.error, "Theme apply failed")
                    test.check(backend.action.command[2] === "set" && backend.action.command[3] === "moss", "Wrong theme command")
                    backend.apply("mode", 1)
                    break
                case 2:
                    test.check(backend.error.indexOf("could not be fully applied") !== -1, "Failed apply not reported")
                    test.check(test.desktopTheme.mode === "dark", "Failed apply changed displayed state")
                    backend.helper = "/nonexistent/blankweave-settings-test.sh"
                    backend.refresh()
                    break
                case 3:
                    test.check(backend.error.length > 0, "Missing helper not reported")
                    backend.helper = test.fixture
                    backend.refresh()
                    break
                case 4:
                    test.check(!backend.error && backend.themes.length === 2, "Refresh did not recover")
                    test.check(backend.syncAvailable, "Installed helper was not detected")
                    backend.syncCommand = ["bash", test.fixture, "sync-cancel"]
                    backend.syncSystem()
                    test.check(backend.syncing && backend.busy, "Sync did not lock other actions")
                    break
                case 5:
                    test.check(backend.syncState === "cancelled" && backend.systemPending, "Cancellation lost pending state")
                    backend.syncCommand = ["bash", test.fixture, "sync-denied"]
                    backend.syncSystem()
                    break
                case 6:
                    test.check(backend.syncState === "error" && backend.systemPending, "Authorization failure not reported")
                    backend.syncCommand = ["bash", test.fixture, "sync-fail"]
                    backend.syncSystem()
                    break
                case 7:
                    test.check(backend.syncState === "error" && backend.syncStarted, "Apply failure not reported")
                    backend.syncCommand = ["bash", test.fixture, "sync-incomplete"]
                    backend.syncSystem()
                    break
                case 8:
                    test.check(backend.syncState === "error" && backend.systemPending, "Unverified completion reported as success")
                    backend.syncCommand = ["bash", test.fixture, "sync-success"]
                    backend.syncSystem()
                    break
                case 9:
                    test.check(backend.syncState === "success" && !backend.systemPending, "Successful apply not verified")
                    console.log("SETTINGS_BACKEND_PASSED")
                    Qt.quit()
                    break
                }
            } catch (error) {
                console.error("SETTINGS_BACKEND_FAILED: " + error)
                Qt.quit()
            }
        }
    }
}
