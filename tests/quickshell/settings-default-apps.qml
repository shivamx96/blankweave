import QtQuick
import QtQuick.Layouts
import Quickshell
import "Services"
import "Settings"
import "."
ShellRoot {
    id: test
    property int step: 0
    property var stale: null
    readonly property string fixture: Qt.resolvedUrl("default-apps.py").toString().replace("file://", "")
    Theme { id: theme }
    SettingsDefaultApps { id: backend; helper: test.fixture }
    FloatingWindow {
        visible: true; implicitWidth: 640; implicitHeight: 700
        SettingsDefaultAppsControls { id: controls; width: 580; theme: theme; backend: backend }
    }
    function check(condition, message) { if (!condition) throw new Error("Step " + step + ": " + message) }
    function find(parent, name) {
        if (parent.objectName === name) return parent
        for (const child of parent.children || []) { const result = find(child, name); if (result) return result }
        return null
    }
    Timer {
        interval: 180; running: true; repeat: true
        onTriggered: {
            if (backend.busy) return
            try {
                const choice = test.find(controls, "defaultAppChoice")
                switch (test.step++) {
                case 0:
                    test.check(!backend.active && !backend.ready, "Initially active")
                    backend.active = true
                    break
                case 1:
                    test.check(backend.writable && controls.currentId === "one.desktop", "Initial defaults")
                    test.stale = backend.snapshot()
                    choice.popup.open()
                    // Polling may reorder the live rows while the popup remains open.
                    backend.rows = backend.rows.map(r => Object.assign({}, r, {choices: r.choices.slice().reverse()}))
                    test.check(choice.choices[1].id === "two.desktop", "Open menu identities moved")
                    choice.activated(1); choice.popup.close()
                    test.check(backend.busy && controls.currentId === "one.desktop", "Optimistic update")
                    backend.active = false
                    break
                case 2:
                    test.check(controls.currentId === "two.desktop" && controls.selected.local, "Hidden write did not refresh")
                    backend.apply("browser", "one.desktop", test.stale)
                    break
                case 3:
                    test.check(backend.error.includes("changed") && controls.currentId === "two.desktop", "Stale request accepted")
                    test.find(controls, "defaultAppInherited").clicked()
                    break
                case 4:
                    test.check(controls.currentId === "one.desktop" && !controls.selected.local, "Inherited reset failed")
                    controls.selectedId = "music"
                    test.check(!choice.enabled && choice.displayText.includes("No compatible"), "Empty apps enabled")
                    backend.helper = "/nonexistent/default-apps.py"; backend.refresh(true)
                    break
                case 5:
                    test.check(!backend.ready && !backend.writable, "Read failure permits writes")
                    backend.helper = test.fixture; backend.refresh(true)
                    break
                case 6:
                    test.check(backend.ready && !backend.error, "Retry failed")
                    console.log("SETTINGS_DEFAULT_APPS_PASSED"); Qt.quit()
                }
            } catch (error) { console.error(error); Qt.quit() }
        }
    }
}
