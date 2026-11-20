import QtQuick
import QtTest
import "../../defaults/quickshell/Settings"
TestCase {
    id: test
    name: "SettingsFeedback"
    when: windowShown
    visible: true
    width: 640; height: 600
    property var themePalette: ({
        borderWidth: 1, headingSize: 22, textWeight: 400, headingWeight: 600, motionDuration: 0, motionEasing: Easing.OutCubic,
        spacing: function(name) { return ({xxs:2,xs:4,sm:6,md:8,lg:10,xl:12,section:14,panel:18,content:32,labelGap:5,descriptionGap:9,group:16,page:20,controlInset:24,rowInset:28})[name] },
        designValue: function(group, name, fallback) { return fallback },surfaceRaised:"#223344",surfaceHover:"#334455",surfacePressed:"#445566",
        text:"#ffffff",textMuted:"#aabbcc",accentBright:"#77aaff",accentSurface:"#223355",outline:"#445566",
        critical:"#ff7777",fontFamily:"sans-serif",textSize:13,smallTextSize:12,widgetRadius:4})

    property int writes: 0
    Component { id: rowFactory; SettingsSwitchRow { width: 400; theme: test.themePalette; text: "Wi-Fi"; onClicked: { test.writes++; busy = true } } }
    Component { id: confirmFactory; SettingsConfirmButton { theme: test.themePalette; actionText: "Forget"; confirmText: "Forget “Home Wi-Fi”"; armTimeout: 1000; onConfirmed: test.writes++ } }
    Component { id: focusFactory; SettingsButton { y: 150; theme: test.themePalette; text: "Other" } }
    Component { id: resultFactory; SettingsResult { width: 400; theme: test.themePalette } }
    function init() { writes = 0 }
    function test_pending_settled_no_double_activation() {
        const row = createTemporaryObject(rowFactory, test)
        row.activate(); verify(row.pending); verify(row.requested); verify(!row.checked)
        row.activate(); compare(writes, 1)
        row.checked = true; row.busy = false
        tryCompare(row,"pending",false); verify(row.checked)
    }
    function test_failure_reverts_to_readback_under_control() {
        const row = createTemporaryObject(rowFactory, test)
        row.activate(); row.error = "The password was not accepted."; row.busy = false
        tryCompare(row,"pending",false); verify(!row.checked)
        const message = findChild(row, "settingsResultMessage")
        compare(message.text, row.error); compare(message.color, themePalette.critical)
        tryVerify(() => message.mapToItem(row,0,0).y > findChild(row,"switchControl").mapToItem(row,0,0).y)
        row.activate(); row.error = ""; row.checked = true; row.busy = false
        compare(message.text, "")
    }
    function test_keyboard_space_and_enter() {
        const row = createTemporaryObject(rowFactory, test)
        const control = findChild(row, "switchControl")
        control.forceActiveFocus(); keyClick(Qt.Key_Space); compare(writes, 1)
        row.checked = true; row.busy = false
        tryCompare(row,"pending",false)
        control.forceActiveFocus(); keyClick(Qt.Key_Return); compare(writes, 2)
        compare(control.Accessible.name, "Wi-Fi")
    }
    function test_confirmation_lifecycle() {
        const button = createTemporaryObject(confirmFactory, test)
        button.forceActiveFocus(); keyClick(Qt.Key_Space); verify(button.armed); compare(writes,0)
        keyClick(Qt.Key_Return); compare(writes,1); verify(!button.armed)
        button.armTimeout = 80; button.clicked(); tryCompare(button,"armed",false,500)
        button.armTimeout = 1000
        button.clicked(); keyClick(Qt.Key_Escape); verify(!button.armed)
        button.clicked(); button.targetIdentity = "other"; verify(!button.armed)
        button.clicked(); const other = createTemporaryObject(focusFactory,test); other.forceActiveFocus(); verify(!button.armed)
        button.clicked(); button.visible = false; verify(!button.armed)
    }
    function test_plain_details_and_cancellation_color() {
        const result = createTemporaryObject(resultFactory,test,{message:"Could not apply this change. Try again.",detail:"Diagnostic <b>text</b>"})
        const details = findChild(result,"settingsResultDetails")
        verify(!details.visible); result.expanded = true; verify(details.visible)
        compare(details.textFormat, TextEdit.PlainText)
        result.cancelled = true
        compare(findChild(result,"settingsResultMessage").color,themePalette.textMuted)
        result.message = ""; verify(!result.expanded)
    }
}
