import QtQuick
import QtTest
import "../../defaults/quickshell/Services"
import "../../defaults/quickshell/Modules"
TestCase {
    id: test
    name: "OsdIntent"
    when: windowShown
    QtObject { id: sink; property real volume: .98; property bool muted: false; property var volumes: [.98] }
    QtObject { id: source; property real volume: .6; property bool muted: false; property var volumes: [.6] }
    property var sinkNode: ({id:1,name:"sink",isSink:true,isStream:false,audio:sink})
    property var sourceNode: ({id:2,name:"source",isSink:false,isStream:false,audio:source})
    QtObject {
        id: provider
        property bool ready: true
        property var defaultAudioSink: test.sinkNode
        property var defaultAudioSource: test.sourceNode
        property QtObject nodes: QtObject { property var values: [test.sinkNode,test.sourceNode] }
    }
    AudioInput { id: mic; provider: provider }
    AudioOutput { id: audio; provider: provider; property var microphone: mic }
    OsdService { id: osd; audio: audio; focusedScreenName: "DP-3" }
    QtObject {
        id: theme
        property int osdWidth: 280
        property int osdBarHeight: 4
        property int widgetRadius: 8
        property int borderWidth: 1
        property string panelSurface: "#202020"
        property string outlineStrong: "#808080"
        property string accentBright: "#88aaff"
        property string text: "#ffffff"
        property string surfaceRaised: "#303030"
        property string iconFontFamily: "sans-serif"
        property string fontFamily: "sans-serif"
        property int controlIconSize: 20
        property int textSize: 13
        property int motionDuration: 100
        property bool reducedMotion: false
        function spacing(name) { return 12 }
    }
    OsdCard { id: card; theme: theme; feedback: osd; width: implicitWidth; height: implicitHeight }
    function init() { provider.ready = true; sink.volumes = [.98]; sink.volume = .98; sink.muted = false; source.muted = false; osd.open = false; osd.blocked = false; osd.panels = [] }
    function test_keys_scroll_cap_and_mutes() {
        osd.volume("up"); compare(sink.volume, 1); verify(osd.visible); compare(osd.screenName,"DP-3")
        osd.volume("up"); compare(sink.volume, 1)
        osd.volume("down",2); fuzzyCompare(sink.volume,.9,.00001)
        osd.volume("mute"); verify(sink.muted); compare(osd.level,0)
        osd.micMute(); verify(source.muted); compare(osd.label,"Microphone muted")
        osd.micMute(); verify(!source.muted)
        provider.ready = false; osd.volume("up"); fuzzyCompare(sink.volume,.9,.00001)
    }
    function test_external_changes_and_panels() {
        sink.volume = .4; source.muted = true; verify(!osd.open)
        osd.panel(test,"volume",true); osd.volume("up"); verify(!osd.visible)
        osd.panel(test,"volume",false); verify(!osd.visible)
        osd.volume("down"); verify(osd.visible)
        osd.panel(test,"volume",true); verify(!osd.visible)
        osd.blocked = true; osd.show("brightness","Brightness","x",.5); verify(!osd.visible)
        osd.blocked = false; verify(!osd.visible)
    }
    function test_timer_restart_and_motion() {
        osd.volume("up"); wait(900); osd.volume("down"); wait(750); verify(osd.visible)
        tryCompare(osd,"open",false,1000)
        theme.reducedMotion = true; osd.volume("down"); verify(osd.visible)
        compare(card.implicitWidth,theme.osdWidth); verify(card.implicitHeight > 0)
        theme.reducedMotion = false
    }
}
