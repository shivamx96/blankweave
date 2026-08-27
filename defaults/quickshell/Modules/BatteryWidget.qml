import QtQuick
import Quickshell.Services.UPower
import "../Components"

WidgetFrame {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property int percentage: device && device.ready ? Math.round(Number(device.percentage || 0) * 100) : 0
    readonly property bool charging: device && (device.state === UPowerDeviceState.Charging
        || device.state === UPowerDeviceState.PendingCharge)
    readonly property bool full: device && device.state === UPowerDeviceState.FullyCharged

    function batteryIcon() {
        if (charging)
            return "󰂄"
        if (full || percentage >= 95)
            return "󰁹"
        if (percentage >= 80)
            return "󰂁"
        if (percentage >= 60)
            return "󰁿"
        if (percentage >= 40)
            return "󰁽"
        if (percentage >= 20)
            return "󰁻"
        return "󰂎"
    }

    visible: device && device.ready && device.isPresent && device.isLaptopBattery
    icon: batteryIcon()
    label: full ? "Full" : percentage + "%"
    tooltip: (charging ? "Charging" : (full ? "Fully charged" : "On battery"))
        + " · " + percentage + "%"
    attention: !charging && percentage <= 15
    active: charging
}
