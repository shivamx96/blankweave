import QtQuick
import Quickshell.Services.UPower

// Owned once by PowerService; device is injected rather than discovered here.
QtObject {
    id: root
    property var device: null
    readonly property var thresholds: [20, 10, 5]
    readonly property int recoveryMargin: 5
    property var fired: []
    property int warningLevel: 0
    readonly property bool valid: Boolean(device && device.ready && device.isPresent
        && device.isLaptopBattery && typeof device.percentage === "number"
        && Number.isFinite(device.percentage) && device.percentage >= 0 && device.percentage <= 1)
    readonly property real percentage: valid ? device.percentage * 100 : NaN
    readonly property int state: valid ? device.state : UPowerDeviceState.Unknown
    readonly property bool charging: valid && (state === UPowerDeviceState.Charging
        || state === UPowerDeviceState.FullyCharged || state === UPowerDeviceState.PendingCharge)
    readonly property bool discharging: valid && (state === UPowerDeviceState.Discharging
        || state === UPowerDeviceState.Empty || state === UPowerDeviceState.PendingDischarge)
    // Coalesce a device's property updates before interpreting a transition.
    onValidChanged: Qt.callLater(evaluate)
    onPercentageChanged: Qt.callLater(evaluate)
    onStateChanged: Qt.callLater(evaluate)
    Component.onCompleted: Qt.callLater(evaluate)

    function dismiss() { warningLevel = 0 }
    function evaluate() {
        if (!valid || (!charging && !discharging)) {
            dismiss()
            return // Missing/unknown data never resets the discharge ledger.
        }
        if (charging) {
            fired = []
            dismiss()
            return
        }
        const next = fired.filter(level => percentage < level + recoveryMargin)
        let severe = 0
        for (const level of thresholds) {
            if (percentage <= level && !next.includes(level)) {
                next.push(level) // Consume skipped thresholds too (resume/startup).
                severe = level
            }
        }
        fired = next
        if (severe > 0) {
            warningLevel = severe
            if (severe === 5) expiry.stop()
            else expiry.restart()
        }
    }
    property Timer expiry: Timer {
        interval: 8000
        running: false
        onTriggered: if (root.warningLevel !== 5) root.dismiss()
    }
    onWarningLevelChanged: if (warningLevel === 0 || warningLevel === 5) expiry.stop()
}
