import QtQuick
import QtQuick.Layouts
import Quickshell
import "Services"
import "Settings"
import "."
ShellRoot {
    id: test
    property int step: 0
    readonly property string fixture: Qt.resolvedUrl("interface.py").toString().replace("file://", "")
    Theme { id: theme }
    SettingsInterface { id: backend; helper: test.fixture }
    FloatingWindow {
        visible: true; implicitWidth: 640; implicitHeight: 700
        ColumnLayout {
            width: 580
            SettingsInterfaceSize { id: textControls; theme: theme; backend: backend; settingId: "fonts"; Layout.fillWidth: true }
            SettingsInterfaceSize { id: cursorControls; theme: theme; backend: backend; settingId: "cursor"; Layout.fillWidth: true }
        }
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
                switch (test.step++) {
                case 0:
                    test.check(!backend.ready && !backend.active && theme.textSize === 13, "Initial state")
                    backend.active = true
                    break
                case 1:
                    test.check(backend.writable, "Controls unavailable")
                    test.find(textControls, "interfaceSize_text_scale").activated(2)
                    test.check(backend.busy && backend.saved.text_scale === 1, "Optimistic size")
                    backend.active = false
                    break
                case 2:
                    test.check(backend.saved.text_scale === 1.3 && !backend.active, "Hidden write not verified")
                    test.check(theme.textScale === 1.3 && theme.textSize === 17 && theme.smallTextSize === 16, "Shell font tokens not updated")
                    test.find(cursorControls, "interfaceSize_cursor_size").activated(1)
                    break
                case 3:
                    test.check(backend.saved.cursor_size === 32 && theme.textScale === 1.3, "Pointer write changed text")
                    test.find(cursorControls, "interfaceSize_cursor_size").activated(2)
                    break
                case 4:
                    test.check(backend.error.includes("rejected") && backend.saved.cursor_size === 32, "Rejected pointer change accepted")
                    test.find(textControls, "interfaceSize_text_scale").activated(0)
                    break
                case 5:
                    test.check(theme.textSize === 13 && backend.saved.text_scale === 1, "Default text size not restored")
                    textControls.width = 320
                    backend.helper = "/nonexistent/interface.py"; backend.refresh(true)
                    break
                case 6:
                    test.check(!backend.ready && !backend.writable, "Read failure permits writes")
                    backend.helper = test.fixture; backend.refresh(true)
                    break
                case 7:
                    test.check(backend.ready && !backend.error, "Retry failed")
                    backend.synced = false
                    test.check(!backend.writable, "Unloaded integration permits writes")
                    console.log("SETTINGS_INTERFACE_PASSED"); Qt.quit()
                }
            } catch (error) { console.error(error); Qt.quit() }
        }
    }
}
