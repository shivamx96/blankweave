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
        warning: "#eab875", accent: "#67a6ff", fontFamily: "sans-serif", iconFontFamily: "sans-serif",
        textSize: 13, smallTextSize: 12, microTextSize: 11, widgetRadius: 4, panelRadius: 14
    })
    QtObject {
        id: fakeBackend
        property bool ready: true
        property bool busy: false
        property string error: ""
        property bool systemPending: false
        property bool syncAvailable: true
        property bool syncing: false
        property string syncState: "idle"
        property string syncMessage: ""
        property string pendingDescription: "Folder colors need updating."
        property int syncRequests: 0
        property int writes: 0
        property int selected: 0
        property bool rejectChanges: false
        function choices(id) { return ["First", "Second"] }
        function selection(id) { return selected }
        function apply(id, index) { writes++; if (!rejectChanges) selected = index }
        function refresh() { }
        function syncSystem() { syncRequests++ }
    }
    SettingsContent {
        id: content
        anchors.fill: parent
        theme: test.palette
        appearance: fakeBackend
        displays: fakeDisplays
    }
    QtObject {
        id: fakeDisplays
        property bool ready: true
        property bool busy: false
        property bool loaded: true
        property string error: ""
        property var monitors: [{ name: "eDP-1" }, { name: "DP-3" }]
        property string selectedConnector: "eDP-1"
        property string details: "2880 × 1800 · Active scale 150%"
        property string savedScaleNotice: ""
        property int writes: 0
        property int selected: 2
        property int selectedPosition: 0
        property string lastSetting: ""
        property bool canSelect: !busy
        property bool brightnessAvailable: true
        property bool brightnessHeld: false
        property real brightnessValue: 60
        function label(row) { return row.name }
        function selectDisplay(index) { selectedConnector = monitors[index].name }
        function canApply(id) {
            if (id === "brightness") return brightnessAvailable
            return id !== "arrangement" || (selectedConnector === "DP-3" && monitors.length > 1)
        }
        function description(id) { return id === "arrangement" && !canApply(id) ? "Select an external display." : "" }
        function choices(id) { return id === "arrangement" ? ["Automatic", "Left", "Right", "Above", "Below"] : ["Automatic", "100%", "150%"] }
        function selection(id) { return id === "arrangement" ? selectedPosition : selected }
        function value(id) { return brightnessAvailable ? brightnessValue : -1 }
        function adjust(id, value) { writes++; lastSetting = id; brightnessValue = value }
        function hold(id, pressed) { brightnessHeld = pressed }
        function apply(id, index) {
            writes++; lastSetting = id
            if (id === "arrangement") selectedPosition = index
            else if (id === "brightness") brightnessValue = index
            else selected = index
        }
        function refresh() { }
    }
    SignalSpy { id: closeSpy; target: content; signalName: "closeRequested" }

    function init() {
        fakeBackend.ready = true
        fakeBackend.busy = false
        fakeBackend.writes = 0
        fakeBackend.selected = 0
        fakeBackend.rejectChanges = false
        fakeBackend.error = ""
        fakeBackend.systemPending = false
        fakeBackend.syncAvailable = true
        fakeBackend.syncing = false
        fakeBackend.syncState = "idle"
        fakeBackend.syncMessage = ""
        fakeBackend.syncRequests = 0
        content.selectedPage = "appearance"
        findChild(content, "settingsSearch").text = ""
        closeSpy.clear()
        fakeDisplays.ready = true
        fakeDisplays.busy = false
        fakeDisplays.monitors = [{ name: "eDP-1" }, { name: "DP-3" }]
        fakeDisplays.selectedConnector = "eDP-1"
        fakeDisplays.selected = 2
        fakeDisplays.writes = 0
        fakeDisplays.selectedPosition = 0
        fakeDisplays.lastSetting = ""
        fakeDisplays.brightnessAvailable = true
        fakeDisplays.brightnessHeld = false
        fakeDisplays.brightnessValue = 60
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

    function test_display_controls_route_to_selected_backend() {
        content.selectedPage = "displays"
        wait(20)
        var display = findChild(content, "settingsDisplaySelector")
        var scale = findChild(content, "settingsChoice_scale")
        verify(display !== null && scale !== null)
        verify(display.enabled && scale.enabled)
        compare(scale.currentIndex, 2)
        display.activated(1)
        compare(fakeDisplays.selectedConnector, "DP-3")
        compare(display.currentIndex, 1)
        scale.activated(0)
        compare(fakeDisplays.writes, 1)
        compare(fakeBackend.writes, 0)
        compare(scale.currentIndex, 0)
        fakeDisplays.busy = true
        verify(!display.enabled && !scale.enabled)
        fakeDisplays.busy = false
        fakeDisplays.ready = false
        fakeDisplays.monitors = []
        verify(!display.enabled && !scale.enabled)
        compare(findChild(content, "displayStatus").text, "No connected displays.")
    }

    function test_position_availability_and_routing() {
        content.selectedPage = "displays"
        wait(20)
        var position = findChild(content, "settingsChoice_arrangement")
        var scale = findChild(content, "settingsChoice_scale")
        verify(position !== null && !position.enabled)
        verify(scale.enabled)
        compare(findChild(content, "settingsDescription_arrangement").text, "Select an external display.")
        findChild(content, "settingsDisplaySelector").activated(1)
        verify(position.enabled)
        position.activated(3)
        compare(fakeDisplays.lastSetting, "arrangement")
        compare(position.currentIndex, 3)
        compare(scale.currentIndex, 2)
        fakeDisplays.busy = true
        verify(!position.enabled)
        fakeDisplays.busy = false
        fakeDisplays.monitors = [{ name: "DP-3" }]
        verify(!position.enabled)
        verify(scale.enabled)
        compare(fakeDisplays.writes, 1)
    }

    function test_brightness_slider_keyboard_and_availability() {
        content.selectedPage = "displays"
        wait(20)
        var slider = findChild(content, "settingsSlider_brightness")
        verify(slider !== null && slider.enabled)
        compare(slider.value, 60)
        slider.forceActiveFocus()
        keyClick(Qt.Key_Right)
        compare(fakeDisplays.lastSetting, "brightness")
        compare(fakeDisplays.brightnessValue, 61)
        fakeDisplays.brightnessValue = 35
        compare(slider.value, 35)
        fakeDisplays.brightnessAvailable = false
        verify(!slider.enabled)
        var writes = fakeDisplays.writes
        keyClick(Qt.Key_Right)
        compare(fakeDisplays.writes, writes)
    }

    function test_brightness_drag_releases_backend_on_page_change() {
        content.selectedPage = "displays"
        wait(20)
        var slider = findChild(content, "settingsSlider_brightness")
        mousePress(slider, slider.width / 2, slider.height / 2)
        verify(fakeDisplays.brightnessHeld)
        content.selectedPage = "appearance"
        wait(20)
        verify(!fakeDisplays.brightnessHeld)
        mouseRelease(content, 10, 10)
        compare(fakeBackend.writes, 0)
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

    function test_system_appearance_requires_explicit_action() {
        fakeBackend.systemPending = true
        var button = findChild(content, "applySystemAppearance")
        verify(button.visible)
        verify(button.enabled)
        compare(fakeBackend.syncRequests, 0)
        mouseClick(button)
        compare(fakeBackend.syncRequests, 1)
        fakeBackend.busy = true
        verify(!button.enabled)
        fakeBackend.busy = false
        fakeBackend.syncAvailable = false
        verify(!button.enabled)
        fakeBackend.systemPending = false
        fakeBackend.syncMessage = "System appearance is up to date."
        verify(!button.visible)
        compare(findChild(content, "systemAppearanceProgress").text, fakeBackend.syncMessage)
    }
}
