import QtQuick
import Quickshell
import "Services"
import "Settings"
import "."
ShellRoot {
    id: test
    property int step: 0
    readonly property string fixture: Qt.resolvedUrl("shortcuts.py").toString().replace("file://", "")
    Theme { id: theme }
    SettingsShortcuts { id: backend; helper: test.fixture }
    FloatingWindow {
        visible: true; implicitWidth: 640; implicitHeight: 700
        SettingsShortcutsControls { id: controls; theme: theme; backend: backend; width: 580 }
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
                    test.check(!backend.ready && !backend.active, "Hidden backend polled")
                    backend.active = true
                    break
                case 1:
                    test.check(backend.writable && controls.selected.id === "settings", "Controls unavailable")
                    test.find(controls, "shortcutEdit").clicked()
                    test.find(controls, "shortcutKey").activated(2)
                    test.find(controls, "shortcutSave").clicked()
                    test.check(backend.busy && controls.selected.value === "SUPER + comma", "Optimistic value")
                    backend.active = false
                    break
                case 2:
                    test.check(controls.selected.value === "SUPER + F8" && controls.draft === null && !backend.active, "Hidden write not verified")
                    controls.begin()
                    test.find(controls, "shortcutKey").activated(3)
                    test.find(controls, "shortcutSave").clicked()
                    break
                case 3:
                    test.check(backend.error.includes("conflicts") && controls.selected.value === "SUPER + F8" && controls.draft !== null, "Rejected save accepted or draft lost")
                    controls.draft = null
                    test.find(controls, "shortcutReset").clicked()
                    break
                case 4:
                    test.check(controls.selected.value === "SUPER + comma" && !controls.selected.overridden, "Reset failed")
                    test.find(controls, "shortcutAction").popup.open()
                    break
                case 5:
                    backend.rows = backend.rows.slice().reverse()
                    test.find(controls, "shortcutAction").activated(1)
                    test.find(controls, "shortcutAction").popup.close()
                    test.check(controls.selected.id === "terminal", "Open menu retargeted")
                    test.find(controls, "shortcutSearch").text = "terminal"
                    test.check(controls.rows.length === 1, "Search failed")
                    controls.width = 320
                    backend.helper = "/nonexistent/shortcuts.py"; backend.refresh(true)
                    break
                case 6:
                    test.check(!backend.ready && !backend.writable && controls.selected === null, "Read failure kept writable values")
                    backend.helper = test.fixture; backend.refresh(true)
                    break
                case 7:
                    test.check(backend.ready && !backend.error, "Retry failed")
                    backend.installed = false
                    test.check(!backend.writable, "Missing integration permits edits")
                    console.log("SETTINGS_SHORTCUTS_PASSED"); Qt.quit()
                }
            } catch (error) { console.error(error); Qt.quit() }
        }
    }
}
