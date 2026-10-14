import QtQuick
import Quickshell
import "Services"
import "Settings"
import "."
ShellRoot {
    id: test
    property int step: 0
    readonly property string fixture: Qt.resolvedUrl("keyboard.py").toString().replace("file://", "")
    Theme { id: theme }
    SettingsKeyboard { id: backend; helper: test.fixture }
    FloatingWindow {
        visible: true; implicitWidth: 640; implicitHeight: 700
        SettingsKeyboardControls { id: controls; theme: theme; backend: backend; width: 580 }
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
                    test.check(!backend.ready && !backend.active, "Hidden keyboard view polled")
                    backend.active = true
                    break
                case 1:
                    test.check(backend.ready && backend.writable, "Controls unavailable")
                    test.find(controls, "keyboardEdit").clicked()
                    test.check(controls.draft.length === 1, "Draft lost current layout")
                    test.find(controls, "keyboardAdd").popup.open()
                    break
                case 2:
                    test.find(controls, "keyboardAdd").activated(0)
                    test.find(controls, "keyboardAdd").popup.close()
                    test.check(controls.draft.length === 2 && controls.draft[1].layout === "de", "Wrong layout added")
                    test.find(controls, "keyboardShortcut").activated(1)
                    test.check(controls.options === "caps:escape,grp:alt_shift_toggle", "Unrelated options lost")
                    test.find(controls, "keyboardSave").clicked()
                    test.check(backend.busy && backend.values.kb_layout === "us", "Optimistic layout state")
                    backend.active = false
                    break
                case 3:
                    test.check(backend.values.kb_layout === "us,de" && !backend.active, "Hidden save not refreshed")
                    test.find(controls, "keyboardNext").clicked()
                    break
                case 4:
                    test.check(controls.currentKeyboard.active_keymap === "German", "Live switch not verified")
                    controls.selectedKeyboard = Object.assign({}, controls.currentKeyboard)
                    backend.devices = [Object.assign({}, backend.devices[0], {address: "0xNEW"})]
                    test.check(controls.currentKeyboard === null && !test.find(controls, "keyboardNext").enabled, "Replacement keyboard retargeted")
                    controls.begin(); controls.move(1)
                    test.check(controls.draft[0].layout === "de", "Reorder failed")
                    test.find(controls, "keyboardSave").clicked()
                    break
                case 5:
                    test.check(backend.error.includes("overrides") && backend.values.kb_layout === "us,de", "Rejected save accepted")
                    controls.width = 320
                    backend.helper = "/nonexistent/keyboard.py"; backend.refresh(true)
                    break
                case 6:
                    test.check(!backend.ready && !backend.writable, "Read failure permits writes")
                    backend.helper = test.fixture; backend.refresh(true)
                    break
                case 7:
                    test.check(backend.ready && !backend.error, "Retry failed")
                    backend.values = Object.assign({}, backend.values, {kb_file: "custom.xkb"})
                    test.check(!backend.writable, "Custom keymap writable")
                    console.log("SETTINGS_KEYBOARD_PASSED"); Qt.quit()
                }
            } catch (error) { console.error(error); Qt.quit() }
        }
    }
}
