import QtQuick
import QtTest
import "../../defaults/quickshell/Services"
import "../../defaults/quickshell/Modules"

TestCase {
    id: test
    name: "Welcome"
    when: windowShown
    width: 600; height: 600
    QtObject { id: prefs; property bool ready: true; property bool welcomeShown: false }
    WelcomeState { id: state; preferences: prefs }
    QtObject {
        id: theme
        property bool reducedMotion: false
        property int osdWidth: 280
        property int widgetRadius: 8
        property int borderWidth: 1
        property color panelSurface: "#202020"
        property color outline: "#808080"
        property color text: "#ffffff"
        property color focusIndicator: "#ffffff"
        property color accentBright: "#99aaff"
        property color critical: "#ff8888"
        property string fontFamily: "sans-serif"
        property string iconFontFamily: "sans-serif"
        property int smallTextSize: 14
        property int iconSize: 16
        property int motionDuration: reducedMotion ? 0 : 100
        property int motionEasing: Easing.OutCubic
        function spacing(name) { return 12 }
    }
    WelcomeCard {
        id: card
        theme: theme
        width: implicitWidth; height: implicitHeight
        onDismissed: state.dismiss()
    }
    SignalSpy { id: dismissed; target: card; signalName: "dismissed" }
    function init() {
        prefs.ready = false; prefs.welcomeShown = false
        state.eligible = false; state.requested = false; state.presented = false
        state.busy = false; state.blocked = false
        prefs.ready = true
        dismissed.clear()
    }
    function test_fresh_upgrade_and_preference_gate() {
        verify(!state.visible) // upgrade: no first-install eligibility marker
        state.eligible = true; verify(state.visible)
        state.dismiss(); verify(prefs.welcomeShown); verify(!state.visible)
        state.eligible = false; state.reopen(); verify(state.visible)
        state.dismiss(); verify(!state.visible)
        prefs.ready = false; state.reopen(); verify(!state.visible)
    }
    function test_busy_priority_and_activity() {
        state.busy = true; state.eligible = true; verify(!state.visible)
        state.activity(); verify(!prefs.welcomeShown)
        state.busy = false; verify(state.visible)
        state.blocked = true; verify(!state.visible)
        verify(!prefs.welcomeShown) // battery interruption is not dismissal
        state.blocked = false; verify(state.visible)
        state.activity(); verify(prefs.welcomeShown); verify(!state.visible)
    }
    function test_keys_button_and_motion() {
        for (const key of [Qt.Key_Escape, Qt.Key_Return, Qt.Key_Enter]) {
            state.reopen(); card.forceActiveFocus(); keyClick(key)
            verify(prefs.welcomeShown); verify(!state.visible)
        }
        state.reopen()
        findChild(card, "welcomeGotIt").pressed()
        verify(!state.visible)
        compare(dismissed.count, 4)
        theme.reducedMotion = true; state.reopen()
        verify(state.visible); compare(theme.motionDuration, 0)
        theme.reducedMotion = false
    }
    function allText(item) {
        let result = item.text || ""
        for (const child of item.children || []) result += "\n" + allText(child)
        return result
    }
    function test_content() {
        const content = allText(card)
        for (const key of ["Super+Space", "Super+Return", "Super+,", "Super+/", "Super+Escape", "Got it"])
            verify(content.includes(key), key)
    }
}
