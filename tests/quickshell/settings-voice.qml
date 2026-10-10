import QtQuick
import Quickshell
import "Services"

ShellRoot {
    id: test
    property int step: 0
    readonly property string fixture: Qt.resolvedUrl("voice.sh").toString().replace("file://", "")
    Voxtype {
        id: voice
        configPath: Qt.resolvedUrl("install.conf").toString().replace("file://", "")
        transcriptPath: Qt.resolvedUrl("transcript.json").toString().replace("file://", "")
        healthCommand: test.fixture + " health"
        statusCommand: test.fixture + " watch"
        recordCommand: test.fixture
        restartCommand: [test.fixture, "restart"]
    }
    function check(condition, message) { if (!condition) throw new Error(message) }
    function status(state) { voice.updateStatus(JSON.stringify({alt:state,model:"fixture-model",device:"default",backend:"whisper"})) }
    Timer {
        interval: 60
        running: true
        repeat: true
        onTriggered: {
            try {
                switch (test.step) {
                case 0:
                    if (!voice.available) return
                    test.check(voice.canStart && voice.canRestart, "Idle service controls unavailable")
                    voice.record("start", true)
                    voice.record("start", true)
                    test.check(voice.commandBusy && !voice.canStart, "Duplicate command not blocked")
                    break
                case 1:
                    test.check(voice.commandBusy, "Command completion treated as observed recording")
                    test.status("recording")
                    break
                case 2:
                    if (voice.commandBusy) return
                    test.check(voice.canStop && voice.canCancel && !voice.canRestart, "Recording guards failed")
                    voice.restart() // Must not interrupt recording.
                    voice.record("stop")
                    break
                case 3: test.status("transcribing"); break
                case 4:
                    if (voice.commandBusy) return
                    test.check(!voice.canStart && !voice.canRestart && voice.canCancel, "Transcription guards failed")
                    voice.restart()
                    voice.record("cancel")
                    break
                case 5: test.status("idle"); break
                case 6:
                    if (voice.commandBusy) return
                    test.status("streaming")
                    test.check(voice.busy && !voice.canRestart && voice.canCancel, "Streaming treated as idle")
                    voice.restart()
                    voice.record("start")
                    test.status("idle")
                    voice.restartCommand = [test.fixture, "fail"]
                    voice.restart()
                    break
                case 7:
                    if (voice.commandBusy) return
                    test.check(voice.actionError !== "", "Failed restart not reported")
                    test.status("idle")
                    voice.restartCommand = [test.fixture, "restart"]
                    voice.restart()
                    break
                case 8:
                    if (voice.commandBusy) return
                    test.check(voice.available && !voice.actionError, "Restart did not reconnect status")
                    test.check(voice.model === "fixture-model", "Confirmed model missing")
                    voice.statusSeen = false
                    test.check(!voice.canStart && !voice.canRestart, "Unknown running state allowed writes")
                    voice.daemonRunning = false
                    test.check(voice.canRestart, "Stopped service cannot recover")
                    test.status("idle")
                    voice.daemonRunning = true
                    voice.record("start", true)
                    break
                case 9:
                    if (voice.commandBusy) return
                    test.check(voice.actionError.includes("not confirmed"), "Missing state confirmation not reported")
                    voice.featureEnabled = false
                    voice.record("start", true)
                    voice.restart()
                    test.check(!voice.commandBusy, "Disabled profile permitted actions")
                    console.log("SETTINGS_VOICE_PASSED")
                    Qt.quit()
                    break
                }
                test.step++
            } catch (error) { console.error(error); Qt.quit() }
        }
    }
}
