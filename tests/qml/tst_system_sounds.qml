import QtQuick
import QtTest
import "../../defaults/quickshell/Settings"

TestCase {
    id: test
    name: "SystemSounds"
    when: windowShown
    visible: true
    width: 660; height: 500
    property var themePalette: ({surfaceRaised:"#223344",surfaceHover:"#334455",surfacePressed:"#445566",
        text:"#ffffff",textMuted:"#aabbcc",accentBright:"#77aaff",accentSurface:"#223355",outline:"#445566",
        critical:"#ff7777",fontFamily:"sans-serif",textSize:13,smallTextSize:12,widgetRadius:4})
    QtObject {
        id: backend
        property bool ready: true
        property bool busy: false
        property bool gtkSynced: false
        property bool previewAvailable: true
        property string error: ""
        property var preferences: ({"event-sounds":true,"input-feedback-sounds":false,"theme-name":"default"})
        property var writable: ({"event-sounds":true,"input-feedback-sounds":true,"theme-name":true})
        property var themes: [{id:"default",name:"Default"},{id:"custom",name:"Custom"}]
        property var calls: []
        readonly property bool canPreview: ready && !busy && previewAvailable && preferences["event-sounds"]
        function apply(key,value) { calls=calls.concat([[key,value]]) }
        function preview() { calls=calls.concat([["preview"]]) }
        function sync() { calls=calls.concat([["sync"]]) }
        function refresh(clear) { calls=calls.concat([["refresh",clear]]) }
    }
    SettingsSystemSoundsControls { id: controls; theme: test.themePalette; backend: backend; width: 620; x: 20; y: 20 }
    function init() {
        findChild(controls,"systemSoundTheme").popup.close()
        backend.ready=true; backend.busy=false; backend.error=""; backend.gtkSynced=false
        backend.preferences={"event-sounds":true,"input-feedback-sounds":false,"theme-name":"default"}
        backend.writable={"event-sounds":true,"input-feedback-sounds":true,"theme-name":true}
        backend.themes=[{id:"default",name:"Default"},{id:"custom",name:"Custom"}]
        backend.calls=[]
        wait(0)
    }
    function test_toggles_follow_confirmed_state() {
        const toggle=findChild(controls,"eventSoundsToggle")
        toggle.clicked()
        compare(backend.calls[0][0],"event-sounds"); compare(backend.calls[0][1],false)
        compare(toggle.text,"Event sounds: On")
        backend.preferences={"event-sounds":false,"input-feedback-sounds":true,"theme-name":"default"}
        compare(toggle.text,"Event sounds: Off")
        verify(!findChild(controls,"inputSoundsToggle").enabled)
        verify(!findChild(controls,"systemSoundPreview").enabled)
    }
    function test_readonly_unavailable_and_busy_controls() {
        backend.writable={}
        verify(!findChild(controls,"eventSoundsToggle").enabled)
        backend.ready=false
        compare(findChild(controls,"eventSoundsToggle").text,"Event sounds: —")
        verify(!findChild(controls,"systemSoundTheme").enabled)
        backend.busy=true
        verify(!findChild(controls,"systemSoundRefresh").enabled)
    }
    function test_theme_menu_keeps_identity_during_changes() {
        const choice=findChild(controls,"systemSoundTheme")
        choice.popup.open(); tryCompare(choice.popup,"opened",true)
        backend.themes=[{id:"default",name:"Default"}]
        choice.popup.close(); choice.activated(1)
        compare(backend.calls[0][1],"custom") // Backend revalidates this ID, never another index.
        compare(backend.preferences["theme-name"],"default")
    }
    function test_preview_sync_and_failure() {
        findChild(controls,"systemSoundPreview").clicked()
        compare(backend.calls[0][0],"preview")
        findChild(controls,"systemSoundSync").clicked()
        compare(backend.calls[1][0],"sync")
        backend.gtkSynced=true
        verify(!findChild(controls,"systemSoundSync").visible)
        backend.error="Could not play sound"
        compare(findChild(controls,"systemSoundStatus").text,backend.error)
    }
}
