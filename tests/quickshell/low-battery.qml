import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import "Services"
import "Modules"

ShellRoot {
    id: root
    property int step: 0
    property var levels: []
    QtObject {
        id: battery
        property bool ready: true
        property bool isPresent: true
        property bool isLaptopBattery: true
        property real percentage: .8
        property int state: UPowerDeviceState.Discharging
    }
    // Never discover the host battery or run a real profile/power action.
    property PowerService power: PowerService {
        batteryDevice: battery
        helper: Quickshell.env("LOW_BATTERY_HELPER")
        function suspend() { root.suspendCalls++ }
    }
    property int suspendCalls: 0
    property Theme theme: Theme { reducedMotion: true }
    LowBatteryCard {
        id: toast
        theme: root.theme
        power: root.power

    }
    property Connections observed: Connections {
        target: root.power.lowBattery
        function onWarningLevelChanged() {
            if (root.power.lowBattery.warningLevel) root.levels.push(root.power.lowBattery.warningLevel)
        }
    }
    function check(value, message) { if (!value) throw new Error("Low battery step " + step + ": " + message) }
    function findChild(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const found = findChild(child, name)
            if (found) return found
        }
        return null
    }
    function expect(level, count) {
        check(power.lowBattery.warningLevel === level, "warning level " + level)
        check(levels.length === count, "warning count " + count + " got " + levels)
    }
    Timer {
        interval: 40; repeat: true; running: true
        onTriggered: {
            try {
                switch (root.step++) {
                case 0: root.expect(0, 0); battery.percentage = .20; break
                case 1: root.expect(20, 1); power.lowBattery.dismiss(); battery.percentage = .21; break
                case 2: battery.percentage = .19; break
                case 3: root.expect(0, 1); battery.percentage = .10; break
                case 4: root.expect(10, 2); power.lowBattery.dismiss(); battery.percentage = .11; break
                case 5: battery.percentage = .09; break
                case 6: root.expect(0, 2); battery.percentage = .05; break
                case 7:
                    root.expect(5, 3)
                    root.check(!power.lowBattery.expiry.running, "critical never expires")
                    battery.percentage = .06; power.lowBattery.dismiss(); break
                case 8: battery.percentage = .04; break
                case 9: root.expect(0, 3); battery.state = UPowerDeviceState.Charging; break
                case 10: root.expect(0, 3); battery.state = UPowerDeviceState.Discharging; break
                case 11: root.expect(5, 4); root.check(power.lowBattery.fired.length === 3, "jump consumes all thresholds"); power.lowBattery.dismiss(); break
                case 12: battery.percentage = .25; break
                case 13: battery.percentage = .20; break
                case 14: root.expect(20, 5); battery.state = UPowerDeviceState.PendingCharge; break
                case 15: root.expect(0, 5); battery.state = UPowerDeviceState.Unknown; battery.percentage = .02; break
                case 16: root.expect(0, 5); battery.isPresent = false; battery.state = UPowerDeviceState.Discharging; break
                case 17: root.expect(0, 5); battery.isPresent = true; battery.ready = false; break
                case 18: root.expect(0, 5); battery.ready = true; battery.isLaptopBattery = false; break
                case 19: root.expect(0, 5); battery.isLaptopBattery = true; battery.percentage = NaN; break
                case 20: root.expect(0, 5); battery.percentage = .04; break
                case 21:
                    root.expect(5, 6)
                    findChild(toast, "lowBatterySuspend").pressed()
                    root.expect(0, 6); root.check(root.suspendCalls === 1, "suspend only uses injected action")
                    power.batteryDevice = null; break
                case 22:
                    root.expect(0, 6)
                    // A new watcher starting below all thresholds emits only 5.
                    const fresh = startup.createObject(root, {device: battery})
                    root.fresh = fresh
                    break
                case 23:
                    root.check(root.fresh.warningLevel === 5 && root.fresh.fired.length === 3, "startup below threshold")
                    battery.state = UPowerDeviceState.FullyCharged; break
                case 24:
                    root.check(root.fresh.warningLevel === 0 && root.fresh.fired.length === 0, "full dismisses and rearms")
                    battery.state = UPowerDeviceState.Empty; break
                case 25:
                    root.check(root.fresh.warningLevel === 5, "empty is battery even without OnBattery")
                    root.fresh.destroy(); root.fresh = null
                    battery.state = UPowerDeviceState.PendingDischarge
                    battery.percentage = .18
                    root.fresh = startup.createObject(root, {device: battery})
                    break
                case 26:
                    root.check(root.fresh.warningLevel === 20, "startup at 18, pending discharge")
                    root.check(root.fresh.expiry.running && root.fresh.expiry.interval === 8000, "eight-second expiry")
                    root.fresh.expiry.interval = 10; root.fresh.expiry.restart(); break
                case 27:
                    root.check(root.fresh.warningLevel === 0, "noncritical auto-dismisses")
                    root.fresh.destroy(); root.fresh = null
                    battery.percentage = .08
                    root.fresh = startup.createObject(root, {device: battery}); break
                case 28:
                    root.check(root.fresh.warningLevel === 10, "startup at 8 skips 20")
                    battery.state = UPowerDeviceState.Unknown; break
                case 29:
                    root.check(root.fresh.warningLevel === 0 && root.fresh.fired.length === 2, "unknown preserves ledger")
                    battery.state = UPowerDeviceState.Discharging; break
                case 30:
                    root.check(root.fresh.warningLevel === 0, "known again does not replay")
                    battery.percentage = 1.01; break
                case 31:
                    root.check(!root.fresh.valid, "out-of-range data inert")
                    console.log("LOW_BATTERY_PASSED"); Qt.quit()
                }
            } catch (error) { console.error(error); Qt.quit() }
        }
    }
    property var fresh: null
    Component { id: startup; LowBatteryWatcher {} }
}
