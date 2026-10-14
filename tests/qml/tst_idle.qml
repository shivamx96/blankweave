import QtQuick
import QtTest
import "../../defaults/quickshell/Settings"

TestCase {
    id: test
    name: "IdleSettings"
    when: windowShown
    visible: true
    width: 660; height: 600
    property var themePalette: ({surfaceRaised:"#223344",surfaceHover:"#334455",surfacePressed:"#445566",
        text:"#ffffff",textMuted:"#aabbcc",accentBright:"#77aaff",accentSurface:"#223355",outline:"#445566",
        warning:"#ffaa33",fontFamily:"sans-serif",textSize:13,smallTextSize:12,widgetRadius:4})
    QtObject {
        id: backend
        property bool ready: true
        property bool busy: false
        property bool managed: true
        property bool running: true
        property bool battery: true
        property string message: "Idle settings are active."
        property string error: ""
        property var delays: [0,60,120,150,300,360,600,900,1800,3600,7200]
        property var labels: ["Never","1 minute","2 minutes","2½ minutes","5 minutes","6 minutes","10 minutes","15 minutes","30 minutes","1 hour","2 hours"]
        property var settings: ({version:1,ac:{dim:150,lock:300,screen:600,suspend:0},battery:{dim:150,lock:300,screen:360,suspend:1800}})
        property var calls: []
        function apply(mode,key,value) { calls=calls.concat([[mode,key,value]]) }
        function refresh(clear) { calls=calls.concat([["refresh",clear]]) }
    }
    SettingsIdleControls { id: controls; theme: test.themePalette; backend: backend; width: 620; x: 20; y: 20 }
    function init() {
        backend.ready=true; backend.busy=false; backend.managed=true; backend.running=true
        backend.battery=true; backend.error=""; backend.calls=[]
        backend.settings={version:1,ac:{dim:150,lock:300,screen:600,suspend:0},battery:{dim:150,lock:300,screen:360,suspend:1800}}
        controls.width=620
        wait(0)
    }
    function test_independent_source_controls_and_no_optimistic_update() {
        const ac=findChild(controls,"idle_ac_screen")
        compare(ac.currentIndex,6)
        ac.activated(9)
        compare(backend.calls[0][0],"ac"); compare(backend.calls[0][1],"screen"); compare(backend.calls[0][2],3600)
        compare(ac.currentIndex,6)
        const battery=findChild(controls,"idle_battery_suspend")
        battery.activated(0)
        compare(backend.calls[1][0],"battery"); compare(backend.calls[1][1],"suspend"); compare(backend.calls[1][2],0)
        compare(battery.currentIndex,8)
    }
    function test_dim_and_lock_can_be_disabled_independently() {
        findChild(controls,"idle_ac_dim").activated(0)
        findChild(controls,"idle_battery_lock").activated(0)
        compare(backend.calls[0][0],"ac"); compare(backend.calls[0][1],"dim"); compare(backend.calls[0][2],0)
        compare(backend.calls[1][0],"battery"); compare(backend.calls[1][1],"lock"); compare(backend.calls[1][2],0)
    }
    function test_unavailable_custom_and_busy() {
        const choice=findChild(controls,"idle_ac_screen")
        backend.managed=false; verify(!choice.enabled)
        backend.managed=true; backend.running=false; verify(!choice.enabled)
        backend.running=true; backend.busy=true; verify(!choice.enabled)
        backend.busy=false; backend.ready=false; verify(!choice.enabled)
        compare(choice.currentIndex,-1)
    }
    function test_desktop_hides_battery_controls_and_narrow_layout() {
        backend.battery=false
        wait(0)
        verify(findChild(controls,"idle_battery_screen") === null)
        controls.width=350
        wait(0)
        verify(findChild(controls,"idle_ac_screen").width <= 350)
    }
    function test_error_and_refresh() {
        backend.error="Could not save preferences"
        compare(findChild(controls,"idleStatus").text,backend.error)
        findChild(controls,"idleRefresh").clicked()
        compare(backend.calls[0][0],"refresh"); compare(backend.calls[0][1],true)
    }
}
