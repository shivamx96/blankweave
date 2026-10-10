import QtQuick
import QtTest
import "../../defaults/quickshell/Services"
import "../../defaults/quickshell/Settings"

TestCase {
    id: test
    name: "SoundOutput"
    when: windowShown
    visible: true
    width: 640
    height: 420
    property var themePalette: ({
        surfaceRaised:"#1c2940", surfaceHover:"#263955", surfacePressed:"#304563", panelSurface:"#111a2a",
        text:"#e7edf7", textMuted:"#a1aec4", accentBright:"#67a6ff", accentSurface:"#1e3556",
        outline:"#33476a", divider:"#23314a", accent:"#67a6ff", fontFamily:"sans-serif",
        smallTextSize:12, textSize:13, widgetRadius:4
    })
    QtObject { id: speakerAudio; property real volume: .8; property bool muted: false; property var volumes: [.8,.8] }
    QtObject { id: headphoneAudio; property real volume: .4; property bool muted: false; property var volumes: [.4,.4] }
    property var speaker: ({id:11,name:"speaker",description:"Speakers",isSink:true,isStream:false,audio:speakerAudio})
    property var headphones: ({id:12,name:"headphones",description:"Headphones",isSink:true,isStream:false,audio:headphoneAudio})
    QtObject {
        id: provider
        property bool ready: true
        property var defaultAudioSink: null
        property var preferredDefaultAudioSink: null
        property QtObject nodes: QtObject { property var values: [] }
    }
    AudioOutput { id: backend; provider: provider }
    SettingsSoundOutput { id: controls; theme: test.themePalette; backend: backend; width: 600; x: 20; y: 20 }

    function init() {
        findChild(controls, "soundOutputDevice").popup.close()
        provider.ready = true
        speakerAudio.volume = .8
        speakerAudio.muted = false
        speakerAudio.volumes = [.8,.8]
        headphoneAudio.volume = .4
        headphoneAudio.muted = false
        provider.nodes.values = [speaker, headphones]
        provider.defaultAudioSink = speaker
        provider.preferredDefaultAudioSink = null
        wait(0)
    }
    function test_filter_and_select_by_identity() {
        provider.nodes.values = [speaker, headphones,
            {id:13,name:"microphone",isSink:false,isStream:false,audio:speakerAudio},
            {id:14,name:"app",isSink:true,isStream:true,audio:speakerAudio},
            {id:15,name:"video",isSink:true,isStream:false,audio:null}, null]
        compare(backend.outputs.length, 2)
        compare(backend.outputs[0].label, "Headphones")
        backend.selectOutput("12:headphones")
        compare(provider.preferredDefaultAudioSink, headphones)
        compare(backend.outputKey, "11:speaker")
        verify(backend.notice.includes("Preferred: Headphones"))
        // Preference is a request, not evidence that PipeWire switched.
        provider.defaultAudioSink = headphones
        compare(backend.outputLabel, "Headphones")
        compare(backend.volume, .4)
        backend.selectOutput("14:app")
        compare(provider.preferredDefaultAudioSink, headphones)
    }
    function test_external_changes_and_limits() {
        const volume = findChild(controls, "soundOutputVolume")
        speakerAudio.volume = .63
        compare(volume.value, 63)
        speakerAudio.muted = true
        compare(findChild(controls, "soundOutputMute").text, "Unmute")
        backend.setOutputVolume(4)
        compare(speakerAudio.volume, 1.5)
        backend.setOutputVolume(-1)
        compare(speakerAudio.volume, 0)
        backend.setOutputVolume(NaN)
        compare(speakerAudio.volume, 0)
        backend.setOutputMuted("true")
        verify(speakerAudio.muted)
    }
    function test_disconnected_and_unbound_outputs() {
        speakerAudio.volumes = []
        verify(!backend.available)
        backend.setOutputVolume(.2)
        compare(speakerAudio.volume, .8)
        provider.nodes.values = []
        verify(!backend.available)
        compare(backend.outputKey, "")
        verify(backend.notice.includes("No audio outputs"))
        verify(!findChild(controls, "soundOutputDevice").enabled)
        verify(!findChild(controls, "soundOutputVolume").enabled)
        verify(!findChild(controls, "soundOutputMute").enabled)
        backend.selectOutput("11:speaker")
        compare(provider.preferredDefaultAudioSink, null)
    }
    function test_connection_loss_blocks_writes() {
        const generation = backend.generation
        provider.ready = false
        verify(!backend.available)
        backend.selectOutput("12:headphones")
        backend.setOutputVolume(.1)
        backend.setOutputMuted(true)
        compare(provider.preferredDefaultAudioSink, null)
        compare(speakerAudio.volume, .8)
        verify(!speakerAudio.muted)
        provider.ready = true
        backend.setOutputVolume(.1, generation)
        compare(speakerAudio.volume, .8)
    }
    function test_default_change_cancels_old_drag() {
        const generation = backend.generation
        provider.defaultAudioSink = null
        provider.defaultAudioSink = headphones
        backend.setOutputVolume(.9, generation)
        backend.setOutputMuted(true, generation)
        compare(headphoneAudio.volume, .4)
        verify(!headphoneAudio.muted)
        const volume = findChild(controls, "soundOutputVolume")
        mousePress(volume, 60, volume.height / 2)
        provider.defaultAudioSink = speaker
        const original = speakerAudio.volume
        mouseMove(volume, 180, volume.height / 2, 20)
        compare(speakerAudio.volume, original)
        mouseRelease(volume, 180, volume.height / 2)
        compare(speakerAudio.volume, original)
        volume.forceActiveFocus()
        keyClick(Qt.Key_Right)
        fuzzyCompare(speakerAudio.volume, original + .01, .0001)
    }
    function test_open_menu_hotplug_does_not_retarget_choice() {
        const choice = findChild(controls, "soundOutputDevice")
        choice.popup.open()
        tryCompare(choice.popup, "opened", true)
        compare(choice.model[0], "Headphones")
        provider.nodes.values = [speaker]
        compare(choice.model[0], "Headphones")
        choice.popup.close()
        choice.activated(0)
        compare(provider.preferredDefaultAudioSink, null)
        tryCompare(choice.popup, "visible", false)
        tryCompare(choice, "count", 1)
        compare(choice.model.length, 1)
        compare(choice.model[0], "Speakers")
    }
    function test_controls_write_and_follow_confirmed_device() {
        const choice = findChild(controls, "soundOutputDevice")
        choice.activated(0)
        compare(provider.preferredDefaultAudioSink, headphones)
        compare(choice.currentIndex, 1)
        provider.defaultAudioSink = headphones
        compare(choice.currentIndex, 0)
        const mute = findChild(controls, "soundOutputMute")
        mute.clicked()
        verify(headphoneAudio.muted)
        compare(mute.text, "Unmute")
        mute.clicked()
        verify(!headphoneAudio.muted)
        const volume = findChild(controls, "soundOutputVolume")
        volume.forceActiveFocus()
        keyClick(Qt.Key_Right)
        fuzzyCompare(headphoneAudio.volume, .41, .0001)
    }
}
