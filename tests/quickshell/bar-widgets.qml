import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "Components"
import "Components/BarHitGeometry.js" as Geometry
import "Modules"
import "Services"

ShellRoot {
    id: test
    Theme { id: theme }
    QtObject {
        id: audio
        property bool available: true
        property bool muted: true
        property real volume: .8
        property string outputKey: "fake"
        property string outputLabel: "Fake output"
        property var outputs: []
        property int generation: 0
        function setVolume(value) { volume = value }
        function setOutputMuted(value) { muted = value }
    }
    QtObject {
        id: battery
        property bool ready: true
        property bool isPresent: true
        property bool isLaptopBattery: true
        property real percentage: .8
        property int state: UPowerDeviceState.Charging
    }
    QtObject {
        id: power
        property var holds: []
        property bool ready: true
        property bool available: true
        property string profileName: "Balanced"
        property string profile: "balanced"
        property string error: ""
        property string explanation: "Fixture"
        property bool automaticEnabled: false
        property string automaticError: ""
        property string degradation: ""
        function canSelect(profile) { return true }
        function setActive(owner, active) {}
    }
    QtObject {
        id: bluetooth
        property var adapter: ({})
        property string error: ""
        property var prompt: null
        property var actionOwner: null
        property string actionName: ""
        property bool enabled: true
        property bool busy: false
        property var deviceRows: []
        property var connectedDevices: [{name:"Fake headset"}]
        function setScanRequest(owner, active) {}
        function cancelForOwner(owner) {}
    }
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 400
        implicitHeight: 100
        property bool atBottom: false
        property var tooltipTarget: null
        property var shell: ({audio: audio, osd: osd, pollers: fakePollers, brightness: fakeBrightness})
        function setVisibilityHold(owner, held) {}
        function hideTooltip(owner) {}
        function showTooltip(owner, text) {}
        function hitBounds(target) { return Geometry.bounds(strip, target, atBottom) }
        Item {
            id: strip
            width: 400; height: 40
            AudioWidget { id: sound; bar: window; theme: theme; x: 12; y: 5; width: 70; height: 30 }
            BatteryWidget { id: charge; bar: window; theme: theme; power: power; device: battery; x: 100; y: 5; width: 70; height: 30 }
            BluetoothWidget { id: radio; bar: window; theme: theme; bluetooth: bluetooth; x: 200; y: 5; width: 70; height: 30 }
        }
    }
    QtObject {
        id: fakeBrightness
        function registerDisplay(display) { display.polling = false; display.active = false }
        function unregisterDisplay(display) {}
    }
    QtObject {
        id: fakePollers
        function acquire(key, view) { return fakeSource }
        function release(key, view) {}
        function configure(key) {}
    }
    QtObject {
        id: fakeSource
        property bool ready: false
        property bool running: false
        property bool stale: false
        property string output: ""
        property string error: ""
        property double lastUpdated: 0
        property string staleText: ""
        property string command: ""
        signal updated(string payload)
        function refresh() {}
    }
    BrightnessWidget { id: displayWidget; parent: window.contentItem; bar: window; theme: theme }
    ControlPanelHeader {
        id: header
        atBottom: window.atBottom
        parent: window.contentItem
        theme: theme
        actions: [{"id":"power", "label":"Turn fixture off", "kind":"switch", "checked":true, "pending":false}]
    }
    function findSwitch(item) {
        if (item.objectName === "headerSwitch") return item
        for (const child of item.children) {
            const found = findSwitch(child)
            if (found) return found
        }
        return null
    }
    property int headerPresses: 0
    property Connections headerEvents: Connections {
        target: header
        function onActionPressed(id) { test.headerPresses++ }
    }
    OsdService { id: osd; audio: audio }
    property int steps: 0
    property Connections scrolling: Connections { target: sound; function onScrolled(count) { test.steps += count } }
    function check(ok, message) { if (!ok) throw new Error(message) }
    function hit(item) { for (const child of item.children) if (child.objectName === "barWidgetHitArea") return child; return null }
    Timer {
        interval: 80; running: true
        onTriggered: {
            try {
                test.check(displayWidget.visible && !displayWidget.display.available, "Display controls remain available without brightness")
                test.check(displayWidget.iconMark === "display", "Unknown brightness uses a display mark without a level")
                osd.open = false
                displayWidget.scrolled(1)
                test.check(!osd.open, "Unavailable brightness scroll emits no OSD")
                const toggle = test.findSwitch(header)
                toggle.forceActiveFocus()
                test.check(toggle.Accessible.name === "Turn fixture off", "switch accessible name")
                test.check(toggle !== null && toggle.visible && toggle.checked && toggle.enabled, "header renders checked switch")
                toggle.clicked()
                test.check(test.headerPresses === 1, "switch emits action")
                header.actions = [{"id":"power", "label":"Turn fixture on", "kind":"switch", "checked":false, "pending":true}]
                // Repeater recreates delegates when the action model changes.
                headerCheck.start()
                test.check(!sound.attention && !sound.active, "mute is neutral")
                test.check(!charge.attention && !charge.active && charge.iconMark === "battery-charging", "charging is neutral with charging glyph")
                test.check(!radio.active && !radio.attention, "connected Bluetooth is neutral")
                audio.volume = .98
                sound.scrolled(1)
                test.check(audio.volume === 1, "bar scroll caps at 100 percent")
                test.check(osd.open && osd.kind === "volume", "bar scroll emits OSD intent")
                audio.volume = 1.3
                sound.scrolled(1)
                test.check(audio.volume === 1.3, "external amplification cannot increase")
                sound.scrolled(-1)
                test.check(Math.abs(audio.volume - 1.25) < .00001, "external amplification lowers by five percent")
                test.steps = 0
                audio.volume = .8
                test.check(!audio.muted, "raising the volume unmutes")
                audio.muted = true
                const muteIcon = sound.iconMark
                audio.muted = false
                test.check(sound.iconMark !== muteIcon, "mute glyph is distinct")
                battery.state = UPowerDeviceState.Discharging
                battery.percentage = .05
                test.check(charge.attention && !charge.active, "critical battery needs attention")
                bluetooth.enabled = false
                test.check(radio.iconMark === "bluetooth-off" && !radio.attention, "radio off is neutral")
                for (const bottom of [false, true]) {
                    window.atBottom = bottom
                    const first = test.hit(sound), middle = test.hit(charge), last = test.hit(radio)
                    test.check(first.x + sound.x === 0, "first owns corner")
                    test.check(last.x + radio.x + last.width === strip.width, "last owns corner")
                    test.check(first.x + sound.x + first.width === middle.x + charge.x, "no overlapping neighbours")
                    test.check(middle.y + charge.y === (bottom ? 5 : 0), "correct outer edge")
                    test.check(middle.y + charge.y + middle.height === (bottom ? 40 : 35), "correct lower edge")
                }
                sound.accumulateWheel(40, false); sound.accumulateWheel(40, false)
                test.check(test.steps === 0, "small deltas accumulate")
                sound.accumulateWheel(40, false)
                test.check(test.steps === 1, "three deltas make one step")
                sound.accumulateWheel(0, false) // zero and horizontal-only wheel events both have y=0
                test.check(test.steps === 1, "zero vertical emits nothing")
                sound.accumulateWheel(160, false); sound.accumulateWheel(80, false)
                test.check(test.steps === 3 && sound.wheelRemainder === 0, "remainder carries")
                sound.accumulateWheel(40, false); test.hit(sound).exited()
                test.check(sound.wheelRemainder === 0, "exit resets")
                sound.accumulateWheel(120, true)
                test.check(test.steps === 2, "inversion honoured")
                sound.accumulateWheel(40, false)
                pauseCheck.start()
            } catch (error) { console.error(error); Qt.quit() }
        }
    }
    Timer {
        id: headerCheck; interval: 30
        onTriggered: {
            try {
                const toggle = test.findSwitch(header)
                test.check(toggle && !toggle.checked && !toggle.enabled, "pending switch is disabled and reflects backend")
                toggle.clicked()
                test.check(test.headerPresses === 1, "pending cannot activate twice")
            } catch (error) { console.error(error); Qt.quit() }
        }
    }
    Timer {
        id: pauseCheck; interval: 350
        onTriggered: {
            if (sound.wheelRemainder !== 0) { console.error("pause failed to reset"); Qt.quit(); return }
            console.log("BAR_WIDGETS_PASSED")
            Qt.quit()
        }
    }
}
