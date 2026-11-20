import QtQuick
import QtTest
import "../../defaults/quickshell/Launcher/Clipboard.js" as Clipboard

TestCase {
    name: "ClipboardRules"
    function test_deleteEditing() {
        verify(Clipboard.canDelete(4, 4, 4, 4))
        verify(!Clipboard.canDelete(2, 4, 2, 2))
        verify(!Clipboard.canDelete(4, 4, 0, 4))
    }
    function test_emptyDuringReload() {
        verify(!Clipboard.showEmpty(0, true, false, true))
        verify(!Clipboard.showEmpty(0, true, true, true))
        verify(!Clipboard.showEmpty(2, true, true, true))
        verify(Clipboard.showEmpty(0, true, true, false))
    }
}
