import QtQuick
import QtQuick.Controls.Basic
import QtTest
import "../../defaults/quickshell/Settings"

TestCase {
    id: test
    name: "SettingsInputs"
    when: windowShown
    visible: true
    width: 500; height: 400
    property var colors: ({
        borderWidth: 1, headingSize: 22, textWeight: 400, headingWeight: 600, motionDuration: 0, motionEasing: Easing.OutCubic,
        spacing: function(name) { return ({xxs:2,xs:4,sm:6,md:8,lg:10,xl:12,section:14,panel:18,content:32,labelGap:5,descriptionGap:9,group:16,page:20,controlInset:24,rowInset:28})[name] },
        designValue: function(group, name, fallback) { return fallback },text:"#eeeeee",textMuted:"#aaaaaa",surfaceRaised:"#223344",
        accentSurface:"#334455",accentBright:"#77aaff",outline:"#445566",
        fontFamily:"sans-serif",smallTextSize:12,widgetRadius:4,reducedMotion:true})
    Component { id: fieldFactory; SettingsTextField { theme: test.colors; width: 300 } }
    Component { id: areaFactory; SettingsTextArea { theme: test.colors; width: 300; height: 120 } }
    Component { id: switchFactory; SettingsSwitch { theme: test.colors; text: "Enabled" } }
    Component {
        id: scrollingFactory
        Flickable {
            width: 200; height: 200
            contentWidth: width; contentHeight: 100
            ScrollBar.vertical: SettingsScrollBar { objectName: "scrollbar"; theme: test.colors }
        }
    }
    function test_scrollbar_only_appears_for_overflow() {
        const view = createTemporaryObject(scrollingFactory, test)
        const bar = findChild(view, "scrollbar")
        tryCompare(bar, "size", 1)
        verify(!bar.visible)
        view.contentHeight = 400
        tryCompare(bar, "visible", true)
        view.height = 500
        tryCompare(bar, "visible", false)
        view.height = 200
        tryCompare(bar, "visible", true)
        view.contentHeight = 100
        tryCompare(bar, "visible", false)
    }
    function test_inputs_follow_theme_and_disabled_state_data() {
        return [{tag:"single line",factory:fieldFactory},{tag:"multiline",factory:areaFactory}]
    }
    function test_inputs_follow_theme_and_disabled_state(data) {
        const control = createTemporaryObject(data.factory, test)
        const original = test.colors
        try {
            control.forceActiveFocus()
            keyClick(Qt.Key_E)
            compare(control.text, "e")
            compare(control.background.border.color, original.accentBright)
            test.colors = Object.assign({}, original, {text:"#112233",surfaceRaised:"#ffffff",accentSurface:"#ddeeff"})
            compare(control.color, test.colors.text)
            compare(control.background.color, test.colors.surfaceRaised)
            compare(control.selectionColor, test.colors.accentSurface)
            control.enabled = false
            compare(control.color, test.colors.textMuted)
            compare(control.background.opacity, 0.55)
        } finally { test.colors = original }
    }
    function test_password_is_masked() {
        const control = createTemporaryObject(fieldFactory, test, {secret:true,text:"private-value"})
        compare(control.echoMode, TextInput.Password)
        verify(control.displayText !== control.text)
    }
    function test_switch_keyboard_and_disabled_state() {
        const control = createTemporaryObject(switchFactory, test)
        control.forceActiveFocus()
        keyClick(Qt.Key_Space)
        verify(control.checked)
        control.enabled = false
        compare(control.indicator.opacity, 0.55)
    }
}
