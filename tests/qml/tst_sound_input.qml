import QtQuick
import QtTest
import "../../defaults/quickshell/Services"
import "../../defaults/quickshell/Settings"

TestCase {
    id: test
    name: "SoundInput"
    when: windowShown
    visible: true
    width: 640
    height: 420
    property var themePalette: ({
        surfaceRaised:"#1c2940", surfaceHover:"#263955", surfacePressed:"#304563", panelSurface:"#111a2a",
        text:"#e7edf7", textMuted:"#a1aec4", accentBright:"#67a6ff", accentSurface:"#1e3556",
        outline:"#33476a", divider:"#23314a", accent:"#67a6ff", warning:"#ffaa33", fontFamily:"sans-serif",
        smallTextSize:12, textSize:13, widgetRadius:4
    })
    QtObject { id: internalAudio; property real volume: .8; property bool muted: false; property var volumes: [.8,.8] }
    QtObject { id: usbAudio; property real volume: .4; property bool muted: false; property var volumes: [.4,.4] }
    property var internal: ({id:11,name:"internal",description:"Built-in microphone",isSink:false,isStream:false,audio:internalAudio})
    property var usb: ({id:12,name:"usb",description:"External USB microphone",isSink:false,isStream:false,audio:usbAudio})
    QtObject {
        id: provider
        property bool ready: true
        property var defaultAudioSource: null
        property var preferredDefaultAudioSource: null
        property QtObject nodes: QtObject { property var values: [] }
    }
    QtObject {
        id: peakMonitor
        property var node: backend.monitorNode
        property var channels: [1]
        property real peak: .25
    }
    AudioInput { id: backend; provider: provider; monitor: peakMonitor }
    SettingsSoundInput { id: controls; theme: test.themePalette; backend: backend; width: 600; x: 20; y: 20 }

    function init() {
        findChild(controls, "soundInputDevice").popup.close()
        backend.active = false
        peakMonitor.channels = [1]
        peakMonitor.peak = .25
        provider.ready = true
        internalAudio.volume = .8
        internalAudio.muted = false
        internalAudio.volumes = [.8,.8]
        usbAudio.volume = .4
        usbAudio.muted = false
        provider.nodes.values = [internal, usb]
        provider.defaultAudioSource = internal
        provider.preferredDefaultAudioSource = null
        wait(0)
    }
    function test_filter_and_select_by_identity() {
        provider.nodes.values = [internal, usb,
            {id:13,name:"speakers",isSink:true,isStream:false,audio:internalAudio},
            {id:14,name:"app",isSink:false,isStream:true,audio:internalAudio},
            {id:15,name:"video",isSink:false,isStream:false,audio:null}, null]
        compare(backend.inputs.length, 2)
        compare(backend.inputs[1].label, "External USB microphone")
        backend.selectInput("12:usb")
        compare(provider.preferredDefaultAudioSource, usb)
        compare(backend.inputKey, "11:internal")
        verify(backend.notice.includes("Preferred: External USB microphone"))
        // Preference is a request, not evidence that PipeWire switched.
        provider.defaultAudioSource = usb
        compare(backend.inputLabel, "External USB microphone")
        compare(backend.volume, .4)
        backend.selectInput("14:app")
        compare(provider.preferredDefaultAudioSource, usb)
    }
    function test_external_changes_and_limits() {
        const volume = findChild(controls, "soundInputVolume")
        internalAudio.volume = .63
        compare(volume.value, 63)
        internalAudio.muted = true
        compare(findChild(controls, "soundInputMute").text, "Unmute")
        backend.setVolume(4)
        compare(internalAudio.volume, 1.5)
        backend.setVolume(-1)
        compare(internalAudio.volume, 0)
        backend.setVolume(NaN)
        compare(internalAudio.volume, 0)
        backend.setInputMuted("true")
        verify(internalAudio.muted)
    }
    function test_disconnected_and_unbound_inputs() {
        internalAudio.volumes = []
        verify(!backend.available)
        backend.setVolume(.2)
        compare(internalAudio.volume, .8)
        provider.nodes.values = []
        verify(!backend.available)
        compare(backend.inputKey, "")
        verify(backend.notice.includes("No audio inputs"))
        verify(!findChild(controls, "soundInputDevice").enabled)
        verify(!findChild(controls, "soundInputVolume").enabled)
        verify(!findChild(controls, "soundInputMute").enabled)
        backend.selectInput("11:internal")
        compare(provider.preferredDefaultAudioSource, null)
    }
    function test_connection_loss_blocks_writes() {
        const generation = backend.generation
        provider.ready = false
        verify(!backend.available)
        backend.selectInput("12:usb")
        backend.setVolume(.1)
        backend.setInputMuted(true)
        compare(provider.preferredDefaultAudioSource, null)
        compare(internalAudio.volume, .8)
        verify(!internalAudio.muted)
        provider.ready = true
        backend.setVolume(.1, generation)
        compare(internalAudio.volume, .8)
    }
    function test_default_change_cancels_old_drag() {
        const generation = backend.generation
        provider.defaultAudioSource = null
        provider.defaultAudioSource = usb
        backend.setVolume(.9, generation)
        backend.setInputMuted(true, generation)
        compare(usbAudio.volume, .4)
        verify(!usbAudio.muted)
        const volume = findChild(controls, "soundInputVolume")
        mousePress(volume, 60, volume.height / 2)
        provider.defaultAudioSource = internal
        const original = internalAudio.volume
        mouseMove(volume, 180, volume.height / 2, 20)
        compare(internalAudio.volume, original)
        mouseRelease(volume, 180, volume.height / 2)
        compare(internalAudio.volume, original)
        volume.forceActiveFocus()
        keyClick(Qt.Key_Right)
        fuzzyCompare(internalAudio.volume, original + .01, .0001)
    }
    function test_open_menu_hotplug_does_not_retarget_choice() {
        const choice = findChild(controls, "soundInputDevice")
        choice.popup.open()
        tryCompare(choice.popup, "opened", true)
        compare(choice.model[1], "External USB microphone")
        provider.nodes.values = [internal]
        compare(choice.model[1], "External USB microphone")
        choice.popup.close()
        choice.activated(1)
        compare(provider.preferredDefaultAudioSource, null)
        tryCompare(choice.popup, "visible", false)
        tryCompare(choice, "count", 1)
        compare(choice.model.length, 1)
        compare(choice.model[0], "Built-in microphone")
    }
    function test_controls_write_and_follow_confirmed_device() {
        const choice = findChild(controls, "soundInputDevice")
        choice.activated(1)
        compare(provider.preferredDefaultAudioSource, usb)
        compare(choice.currentIndex, 0)
        provider.defaultAudioSource = usb
        compare(choice.currentIndex, 1)
        const mute = findChild(controls, "soundInputMute")
        mute.clicked()
        verify(usbAudio.muted)
        compare(mute.text, "Unmute")
        mute.clicked()
        verify(!usbAudio.muted)
        const volume = findChild(controls, "soundInputVolume")
        volume.forceActiveFocus()
        keyClick(Qt.Key_Right)
        fuzzyCompare(usbAudio.volume, .41, .0001)
    }
    function test_meter_lifecycle_and_signal() {
        compare(backend.monitorNode, null)
        compare(backend.level, 0)
        verify(!backend.levelReady)
        backend.active = true
        compare(backend.monitorNode, internal)
        verify(backend.levelReady)
        compare(backend.level, .25)
        compare(findChild(controls, "soundInputLevel").level, .25)
        internalAudio.volume = .1
        // The native peak monitor measures signal before software gain.
        compare(backend.level, .25)
        peakMonitor.peak = 2
        compare(backend.level, 1)
        peakMonitor.peak = NaN
        compare(backend.level, 0)
        peakMonitor.channels = []
        verify(!backend.levelReady)
        verify(backend.levelNotice.includes("Waiting"))
        peakMonitor.channels = [1]
        internalAudio.muted = true
        compare(backend.monitorNode, null)
        compare(backend.level, 0)
        verify(backend.levelNotice.includes("muted"))
        internalAudio.muted = false
        compare(backend.monitorNode, internal)
        provider.defaultAudioSource = usb
        compare(backend.monitorNode, usb)
        provider.nodes.values = [internal]
        compare(backend.monitorNode, null)
        provider.defaultAudioSource = internal
        compare(backend.monitorNode, internal)
        provider.ready = false
        compare(backend.monitorNode, null)
        provider.ready = true
        backend.active = false
        compare(backend.monitorNode, null)
        verify(!backend.levelReady)
        compare(backend.level, 0)
    }
}
