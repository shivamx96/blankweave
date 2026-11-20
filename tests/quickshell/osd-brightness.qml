import QtQuick
import Quickshell
import Quickshell.Io
import "Services"
import "Modules"
ShellRoot {
    id: test
    property int phase: 0
    QtObject { id: audio; property bool available: false }
    OsdService { id: osd; audio: audio; focusedScreenName: router.focusedScreenName }
    BrightnessRouter {
        id: router
        osd: osd
        screens: [{name:"eDP-1"},{name:"DP-3"}]
        focusedScreenName: "DP-3"
        helper: Qt.resolvedUrl("brightness.sh").toString().replace("file://", "")
    }
    DisplayBrightness {
        id: internal
        screen: ({name:"eDP-1"})
        polling: false
        helper: router.helper
        onStepRequested: value => osd.show("brightness","Brightness · " + value + "%","x",value/100)
    }
    // Typed signatures must be accepted by the installed IpcHandler.
    IpcHandler {
        id: ipc
        target: "fixture-blankweave"
        function brightness(action: string): void { router.adjust(action) }
        function volume(action: string): void { osd.volume(action) }
        function micMute(): void { osd.micMute() }
    }
    function check(ok, message) { if (!ok) throw new Error(message) }
    Timer {
        interval: 30; running: true; repeat: true
        onTriggered: {
            try {
                if (test.phase === 0) { ipc.brightness("up"); test.phase++; return }
                const external = router.cached[0]
                if (!external || external.reading || external.busy || !internal.available) return
                if (test.phase === 1) {
                    test.check(external.connector === "DP-3" && external.percentage === 45,"focused external target")
                    test.check(!external.polling && osd.level === .45 && osd.open,"one-shot OSD feedback")
                    router.registerDisplay(internal); router.focusedScreenName = "eDP-1"
                    ipc.brightness("down"); test.check(osd.level === .55 && internal.confirmedPercentage === 60,"immediate requested level precedes readback"); test.phase++; return
                }
                if (internal.reading || internal.busy) return
                test.check(internal.percentage === 55 && router.cached.length === 1,"reuse focused bar instance: " + internal.percentage + ", cached " + router.cached.length)
                osd.panel(test,"brightness",true); ipc.brightness("up")
                test.check(!osd.visible && internal.percentage === 60,"panel suppresses feedback but accepts key")
                console.log("OSD_BRIGHTNESS_PASSED"); Qt.quit()
            } catch (e) { console.error(e); Qt.quit() }
        }
    }
    Timer { interval: 6000; running: true; onTriggered: Qt.quit() }
}
