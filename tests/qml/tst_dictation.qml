import QtQuick
import QtTest
import "../../defaults/quickshell/Settings"
import "../../defaults/quickshell/Settings/Catalog.js" as Catalog

TestCase {
    id: test
    name: "Dictation"
    when: windowShown
    visible: true
    width: 700
    height: 650
    property var themePalette: ({
        surfaceRaised:"#1c2940", surfaceHover:"#263955", surfacePressed:"#304563",
        text:"#e7edf7", textMuted:"#a1aec4", accentBright:"#67a6ff", accentSurface:"#1e3556",
        outline:"#33476a", critical:"#ff7777", fontFamily:"sans-serif",
        textSize:13, smallTextSize:12, widgetRadius:4
    })
    QtObject {
        id: voice
        property bool featureEnabled: true
        property bool daemonRunning: true
        property bool available: true
        property bool commandBusy: false
        property string daemonState: "idle"
        property string stateLabel: "Ready"
        property string model: "small.en"
        property string device: "default"
        property string backend: "whisper"
        property string actionError: ""
        property string error: ""
        property string lastTranscript: ""
        readonly property bool hasLastTranscript: lastTranscript !== ""
        property bool canStart: true
        property bool canStop: false
        property bool canCancel: false
        property bool canRestart: true
        property var calls: []
        function record(action, clipboard = false) { calls = calls.concat([[action, clipboard]]) }
        function restart() { calls = calls.concat([["restart"]]) }
        function copyTranscript() { calls = calls.concat([["copy"]]) }
    }
    SettingsDictation { id: controls; theme: test.themePalette; backend: voice; width: 650; x: 20; y: 20 }
    function init() {
        voice.featureEnabled = true
        voice.available = true
        voice.daemonRunning = true
        voice.commandBusy = false
        voice.daemonState = "idle"
        voice.stateLabel = "Ready"
        voice.canStart = true
        voice.canStop = false
        voice.canCancel = false
        voice.canRestart = true
        voice.actionError = ""
        voice.lastTranscript = ""
        voice.calls = []
        controls.backend = voice
    }
    function test_clipboard_recording_and_stop() {
        const record = findChild(controls, "dictationRecord")
        record.clicked()
        compare(voice.calls[0][0], "start")
        compare(voice.calls[0][1], true)
        voice.daemonState = "recording"
        voice.stateLabel = "Recording"
        voice.canStart = false
        voice.canStop = true
        compare(record.text, "Stop and transcribe")
        compare(findChild(controls, "dictationStatus").text, "Recording")
        record.clicked()
        compare(voice.calls[1][0], "stop")
    }
    function test_transcribing_disables_restart_and_record() {
        voice.daemonState = "transcribing"
        voice.canStart = false
        voice.canRestart = false
        voice.canCancel = true
        verify(!findChild(controls, "dictationRecord").enabled)
        verify(!findChild(controls, "dictationRestart").enabled)
        const cancel = findChild(controls, "dictationCancel")
        verify(cancel.enabled)
        cancel.clicked()
        compare(voice.calls[0][0], "cancel")
    }
    function test_stopped_service_recovery_and_error() {
        voice.available = false
        voice.daemonRunning = false
        voice.canStart = false
        const restart = findChild(controls, "dictationRestart")
        compare(restart.text, "Start service")
        restart.clicked()
        compare(voice.calls[0][0], "restart")
        voice.actionError = "Could not restart dictation"
        compare(findChild(controls, "dictationError").text, voice.actionError)
        verify(findChild(controls, "dictationError").visible)
    }
    function test_transcript_is_plain_text_and_copy_is_explicit() {
        const copy = findChild(controls, "dictationCopy")
        verify(!copy.visible)
        voice.lastTranscript = "<b>literal transcript</b>\nहिन्दी"
        const transcript = findChild(controls, "dictationTranscript")
        compare(transcript.textFormat, Text.PlainText)
        compare(transcript.text, voice.lastTranscript)
        verify(copy.visible)
        compare(voice.calls.length, 0)
        copy.clicked()
        compare(voice.calls[0][0], "copy")
    }
    function test_missing_profile_and_backend() {
        voice.featureEnabled = false
        verify(!findChild(controls, "dictationRecord").visible)
        controls.backend = null
        verify(!findChild(controls, "dictationRecord").enabled)
        verify(!findChild(controls, "dictationRestart").enabled)
        verify(!findChild(controls, "dictationCopy").visible)
    }
    function test_sound_catalog_removes_mixer_and_keeps_dictation_searchable() {
        const sound = Catalog.pages.find(page => page.id === "sound")
        const rows = sound.groups.reduce((rows, group) => rows.concat(group.rows), [])
        verify(!rows.some(row => row.id === "app-volume"))
        verify(rows.some(row => row.id === "dictation" && row.live))
        verify(Catalog.search("transcript").some(page => page.id === "sound"))
    }
}
