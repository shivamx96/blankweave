import QtQuick
import QtTest
import "../../defaults/quickshell/Settings"
import "../../defaults/quickshell/Components"

TestCase {
    id: test
    name: "ThemeGeometry"
    when: windowShown
    width: 600
    height: 400
    visible: true
    property int textPixels: 13
    property int inset: 12
    property int popupInset: 4
    property real borderPixels: 1
    property var palette: ({
        fontFamily: "sans-serif", textSize: textPixels, smallTextSize: textPixels,
        textWeight: 400, widgetRadius: 4, borderWidth: borderPixels, motionDuration: 0,
        text: "#ffffff", textMuted: "#aaaaaa", accent: "#aabbff", accentBright: "#aabbff",
        accentSurface: "#334466", surfaceRaised: "#222233", surfacePressed: "#333344",
        surfaceHover: "#333344", panelSurface: "#222233", outline: "#777788",
        spacing: function(name) { return name === "xl" ? test.inset : name === "xs" ? test.popupInset : 14 }
    })
    Component { id: buttonFactory; SettingsButton { theme: test.palette; text: "Apply" } }
    Component { id: comboFactory; SettingsComboBox { theme: test.palette; model: ["Speakers", "Headphones"] } }
    Component { id: switchFactory; SettingsSwitch { theme: test.palette; text: "Enabled" } }
    Component { id: fieldFactory; SettingsTextField { theme: test.palette; text: "Input"; width: 300 } }

    Component { id: areaFactory; SettingsTextArea { theme: test.palette; text: "Notes"; width: 300 } }
    Component { id: sharedFieldFactory; ControlTextField { theme: test.palette; text: "Filter"; width: 300 } }

    function cleanup() { textPixels = 13; inset = 12; popupInset = 4; borderPixels = 1 }
    function test_large_theme_text_grows_controls_data() {
        return [
            {tag: "button", factory: buttonFactory},
            {tag: "choice", factory: comboFactory},
            {tag: "switch", factory: switchFactory},
            {tag: "field", factory: fieldFactory}
        ]
    }
    function test_large_theme_text_grows_controls(data) {
        const control = createTemporaryObject(data.factory, test)
        verify(control !== null)
        compare(control.implicitHeight, 36)
        textPixels = 31
        tryVerify(() => control.implicitHeight > 36)
        const textHeight = data.factory === fieldFactory ? control.contentHeight : control.implicitContentHeight
        verify(control.implicitHeight >= textHeight + control.topPadding + control.bottomPadding)
        textPixels = 13
        tryCompare(control, "implicitHeight", 36)
    }
    function test_borderless_theme_retains_keyboard_focus_data() {
        return [
            {tag: "button", factory: buttonFactory},
            {tag: "choice", factory: comboFactory},
            {tag: "switch", factory: switchFactory},
            {tag: "field", factory: fieldFactory},
            {tag: "area", factory: areaFactory},
            {tag: "shared field", factory: sharedFieldFactory}
        ]
    }
    function test_borderless_theme_retains_keyboard_focus(data) {
        borderPixels = 0
        const control = createTemporaryObject(data.factory, test)
        verify(control !== null)
        const outline = data.factory === switchFactory ? control.indicator : control.background
        test.forceActiveFocus()
        tryCompare(outline.border, "width", 0)
        control.forceActiveFocus(Qt.TabFocusReason)
        tryVerify(() => control.activeFocus)
        verify(outline.border.width >= 1)
        test.forceActiveFocus()
        tryCompare(outline.border, "width", 0)
    }
    function test_popup_rows_follow_theme_padding() {
        const combo = createTemporaryObject(comboFactory, test)
        combo.popup.open()
        tryVerify(() => combo.popup.opened)
        const menu = combo.popup.contentItem
        for (const padding of [0, 4, 12, 24]) {
            popupInset = padding
            tryCompare(combo.popup, "padding", padding)
            tryVerify(() => menu.itemAtIndex(0) !== null)
            tryCompare(menu.itemAtIndex(0), "width", menu.width)
            compare(menu.width, combo.popup.availableWidth)
        }
        combo.popup.close()
    }
    function test_theme_spacing_updates_field_insets() {
        const field = createTemporaryObject(fieldFactory, test)
        compare(field.leftPadding, 12)
        inset = 24
        tryCompare(field, "leftPadding", 24)
        compare(field.rightPadding, 24)
    }
}
