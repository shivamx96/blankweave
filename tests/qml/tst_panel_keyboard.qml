import QtQuick
import QtQuick.Layouts
import QtTest
import "../../defaults/quickshell/Components"
import "../../defaults/quickshell/Components/PanelNavigation.js" as Navigation
import "../../defaults/quickshell/Launcher"
import "../../defaults/quickshell/Settings"

TestCase {
    id: test
    name: "PanelKeyboard"
    when: windowShown
    visible: true
    width: 600; height: 500
    property var theme: ({textSize: 13, textWeight: Font.Normal, widgetRadius: 4, canvas: "#111111", surfaceRaised: "#222222", text: "#ffffff", focusIndicator: "#ffffff", textMuted: "#aaaaaa", surfacePressed: "#555555", surfaceHover: "#444444", accentSurface: "#333333", accent: "#88aaff", accentBright: "#88aaff", outlineStrong: "#777777", outline: "#666666", fontFamily: "sans-serif", iconFontFamily: "sans-serif", smallTextSize: 12, microTextSize: 11, iconSize: 14, borderWidth: 1, motionDuration: 0, motionEasing: Easing.Linear, spacing: function() { return 4 }})
    property int activations: 0
    Item {
        id: scope
        anchors.fill: parent
        property var panelController: QtObject {
            property bool keyboardMode: false
            property string focusIdentity: ""
            property Item navigationScope: scope
        }
        ColumnLayout {
            width: 400
            ControlAction { id: action; theme: test.theme; label: "Action"; onPressed: test.activations++ }
            ControlChoice { id: choice; theme: test.theme; text: "Choice"; onPressed: test.activations++ }
            ControlSlider { id: slider; theme: test.theme; stepSize: 5; from: 0; to: 100; value: 50; Layout.fillWidth: true }
            ControlTabs { id: tabs; theme: test.theme; tabs: [{id: "one", label: "One"}, {id: "two", label: "Two"}]; currentId: "one"; onSelected: id => currentId = id }
            ControlTextField { id: field; theme: test.theme; placeholderText: "Search"; Layout.fillWidth: true }
        }
    }
    function init() { activations = 0; scope.panelController.focusIdentity = ""; scope.panelController.keyboardMode = false }
    function focusables() { return Navigation.controls(scope) }
    function test_activation_pressed_and_mouse_ring() {
        const item = focusables()[0]
        item.forceActiveFocus()
        compare(item.panel.keyboardMode, false)
        const ring = item.children.find(c => c.target === item)
        verify(ring !== undefined); compare(ring.visible, false)
        keyPress(Qt.Key_Space)
        verify(item.keyPressed); verify(ring.visible); compare(activations, 0)
        keyRelease(Qt.Key_Space)
        verify(!item.keyPressed); compare(activations, 1)
        keyClick(Qt.Key_Return); compare(activations, 2)
        keyClick(Qt.Key_Tab); verify(focusables()[1].activeFocus)
        keyClick(Qt.Key_Space); compare(activations, 3)
        keyClick(Qt.Key_Tab, Qt.ShiftModifier); verify(item.activeFocus)
    }
    function test_arrows_slider_tabs_and_text() {
        focusables()[0].forceActiveFocus()
        keyClick(Qt.Key_Down); verify(focusables()[1].activeFocus)
        keyClick(Qt.Key_Down); verify(slider.activeFocus)
        slider.value = 50
        keyPress(Qt.Key_Space); verify(slider.pressed)
        keyRelease(Qt.Key_Space); verify(!slider.pressed)
        keyClick(Qt.Key_Right); compare(slider.value, 55)
        keyClick(Qt.Key_Left); compare(slider.value, 50)
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Right); compare(tabs.currentId, "two")
        keyClick(Qt.Key_Left); compare(tabs.currentId, "one")
        keyClick(Qt.Key_End); verify(field.activeFocus)
        field.text = "abc"; field.cursorPosition = 2
        keyClick(Qt.Key_Home); verify(field.activeFocus); compare(field.cursorPosition, 0)
        keyClick(Qt.Key_End); compare(field.cursorPosition, 3)
        keyClick(Qt.Key_Up); verify(field.activeFocus)
    }
    Component { id: rowFactory; ControlMouseArea { theme: test.theme; width: 100; height: 30; onClicked: test.activations++ } }
    function test_refresh_identity_and_no_retarget() {
        const row = createTemporaryObject(rowFactory, scope, {accessibleName: "Device", focusIdentity: "device:A"})
        scope.panelController.focusIdentity = "device:A"
        row.forceActiveFocus()
        keyPress(Qt.Key_Space)
        row.focusIdentity = "device:B"
        keyRelease(Qt.Key_Space)
        compare(activations, 0)
        row.destroy(); wait(1)
        const replacement = createTemporaryObject(rowFactory, scope, {accessibleName: "Device", focusIdentity: "device:A"})
        tryVerify(() => replacement.activeFocus)
        keyClick(Qt.Key_Return); compare(activations, 1)
    }
    Component { id: buttonFactory; SettingsButton { theme: test.theme; text: "Apply"; onClicked: test.activations++ } }
    Component { id: switchFactory; SettingsSwitch { theme: test.theme; text: "Enable"; onClicked: test.activations++ } }
    function test_native_enter_pressed_data() { return [{tag: "button", factory: buttonFactory}, {tag: "switch", factory: switchFactory}] }
    function test_native_enter_pressed(data) {
        const item = createTemporaryObject(data.factory, scope)
        item.forceActiveFocus()
        keyPress(Qt.Key_Return); verify(item.keyPressed); compare(activations, 0)
        keyRelease(Qt.Key_Return); verify(!item.keyPressed); compare(activations, 1)
        keyClick(Qt.Key_Space); compare(activations, 2)
    }
    PanelSession { id: session; screens: [{name: "left"}, {name: "right"}]; focusedScreenName: "right" }
    function test_session_output_unknown_unavailable_and_toggle() {
        const left = {panelId: "audio", bar: {screen: {name: "left"}}, anchorItem: {visible: true}, open: false}
        const right = {panelId: "audio", bar: {screen: {name: "right"}}, anchorItem: {visible: true}, open: false}
        const network = {panelId: "network", bar: {screen: {name: "right"}}, anchorItem: {visible: true}, open: false}
        session.panels = [left, right, network]
        session.request("audio"); verify(right.open); verify(!left.open); compare(session.targetName, "right")
        session.request("missing"); verify(right.open)
        session.request("network"); verify(network.open); verify(!right.open)
        session.request("network"); verify(!session.open); verify(!network.open)
        network.anchorItem.visible = false
        session.request("network"); verify(!session.open)
        session.focusedScreenName = "left"; session.request("audio"); verify(left.open)
        session.screens = [{name: "right"}]
        compare(session.targetName, "right"); verify(right.open); verify(!left.open)
        session.screens = [{name: "left"}, {name: "right"}]
        compare(session.targetName, "right")
        session.dismiss(); session.panels = []; session.focusedScreenName = "right"
    }
}
