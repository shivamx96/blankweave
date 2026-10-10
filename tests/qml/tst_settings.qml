import QtQuick
import QtTest
import "../../defaults/quickshell/Settings"
import "../../defaults/quickshell/Settings/Catalog.js" as Catalog

TestCase {
    id: test
    name: "Settings"
    when: windowShown
    visible: true
    width: 1040
    height: 760

    property var palette: ({
        canvas: "#0b111c", panelSurface: "#111a2a", surface: "#162033",
        surfaceRaised: "#1c2940", surfaceHover: "#263955", surfacePressed: "#304563",
        text: "#e7edf7", textMuted: "#a1aec4", accentBright: "#67a6ff",
        accentSurface: "#1e3556", outline: "#33476a", divider: "#23314a",
        warning: "#eab875", fontFamily: "sans-serif", iconFontFamily: "sans-serif",
        textSize: 13, smallTextSize: 12, microTextSize: 11, widgetRadius: 4, panelRadius: 14
    })
    QtObject {
        id: fakeBackend
        property bool ready: true
        property bool busy: false
        property string error: ""
        property bool systemPending: false
        property int writes: 0
        property int selected: 0
        property bool rejectChanges: false
        function choices(id) { return ["First", "Second"] }
        function selection(id) { return selected }
        function apply(id, index) { writes++; if (!rejectChanges) selected = index }
        function refresh() { }
    }
    SettingsContent {
        id: content
        anchors.fill: parent
        theme: test.palette
        appearance: fakeBackend
    }
    SignalSpy { id: closeSpy; target: content; signalName: "closeRequested" }

    function init() {
        fakeBackend.ready = true
        fakeBackend.busy = false
        fakeBackend.writes = 0
        fakeBackend.selected = 0
        fakeBackend.rejectChanges = false
        fakeBackend.error = ""
        content.selectedPage = "appearance"
        findChild(content, "settingsSearch").text = ""
        closeSpy.clear()
    }

    function test_search_and_empty_state() {
        var search = findChild(content, "settingsSearch")
        search.text = "microphone"
        compare(content.page.id, "sound")
        search.text = "backup retention"
        compare(content.page.id, "storage")
        search.text = "no-match-12345"
        compare(content.page, null)
        compare(content.results.length, 0)
        search.text = ""
        compare(content.results.length, 9)
    }

    function test_pages_at_narrow_width() {
        test.width = 640
        for (var i = 0; i < Catalog.pages.length; i++) {
            content.selectedPage = Catalog.pages[i].id
            wait(20)
            compare(content.page.id, Catalog.pages[i].id)
            verify(findChild(content, "settingsPageScroll").contentWidth > 0)
        }
        compare(fakeBackend.writes, 0)
        test.width = 1040
    }

    function test_keyboard_search_and_escape() {
        var search = findChild(content, "settingsSearch")
        content.focusSearch()
        verify(search.activeFocus)
        search.text = "firmware"
        compare(content.page.id, "system")
        keyClick(Qt.Key_Escape)
        compare(search.text, "")
        compare(closeSpy.count, 0)
        keyClick(Qt.Key_Escape)
        compare(closeSpy.count, 1)
    }

    Component {
        id: rowFactory
        SettingsRow {
            width: 600
            theme: test.palette
            backend: fakeBackend
        }
    }

    function test_preview_never_writes() {
        var row = createTemporaryObject(rowFactory, test, {
            setting: { id: "profile", title: "Power profile", description: "Preview", kind: "choice", options: ["Balanced", "Saver"] }
        })
        verify(row !== null)
        compare(row.live, false)
        compare(row.writable, false)
        compare(fakeBackend.writes, 0)
    }

    function test_live_controls_wait_for_backend() {
        var row = createTemporaryObject(rowFactory, test, {
            setting: { id: "mode", title: "Color mode", description: "Live", kind: "choice", live: true }
        })
        verify(row.live)
        verify(row.writable)
        fakeBackend.busy = true
        verify(!row.writable)
        fakeBackend.busy = false
        fakeBackend.ready = false
        verify(!row.writable)
        fakeBackend.ready = true
        fakeBackend.selected = 1
        compare(row.selection, 1)
    }

    function test_failed_apply_keeps_confirmed_selection() {
        var row = createTemporaryObject(rowFactory, test, {
            setting: { id: "mode", title: "Color mode", description: "Live", kind: "choice", live: true }
        })
        var choice = findChild(row, "settingsChoice_mode")
        verify(choice !== null)
        fakeBackend.rejectChanges = true
        choice.currentIndex = 1
        choice.activated(1)
        compare(fakeBackend.writes, 1)
        compare(choice.currentIndex, 0)
        fakeBackend.selected = 1
        compare(choice.currentIndex, 1)
    }

    Component {
        id: comboFactory
        SettingsComboBox {
            theme: test.palette
            model: ["Dark", "Light"]
        }
    }

    function test_dropdown_tracks_theme_while_open() {
        var combo = createTemporaryObject(comboFactory, test, { x: 400, y: 100 })
        verify(combo !== null)
        var original = test.palette
        try {
            combo.popup.open()
            tryCompare(combo.popup, "opened", true)
            compare(combo.popup.background.color, original.panelSurface)
            compare(combo.contentItem.color, original.text)
            tryVerify(function() { return combo.popup.contentItem.itemAtIndex(1) !== null })
            var option = combo.popup.contentItem.itemAtIndex(1)
            compare(option.contentItem.color, original.text)

            test.palette = Object.assign({}, original, {
                panelSurface: "#f4faf7", surfaceRaised: "#e7f1ec",
                text: "#123329", textMuted: "#526e63", accentBright: "#007c60",
                accentSurface: "#d3ebe2", outline: "#b8d4c7"
            })
            compare(combo.popup.background.color, test.palette.panelSurface)
            compare(combo.contentItem.color, test.palette.text)
            compare(option.contentItem.color, test.palette.text)
            test.palette = original
            compare(combo.popup.background.color, original.panelSurface)
            compare(option.contentItem.color, original.text)
            combo.enabled = false
            compare(combo.contentItem.color, original.textMuted)
            compare(combo.indicator.color, original.textMuted)
        } finally {
            combo.popup.close()
            test.palette = original
        }
    }

    function test_dropdown_keyboard_selection() {
        var combo = createTemporaryObject(comboFactory, test, { x: 400, y: 100 })
        combo.forceActiveFocus()
        keyClick(Qt.Key_Space)
        tryCompare(combo.popup, "opened", true)
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Return)
        compare(combo.currentIndex, 1)
        tryCompare(combo.popup, "opened", false)
    }
}
