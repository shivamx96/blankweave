import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../Components"

WidgetFrame {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool batteryAvailable: Boolean(
        device && device.ready && device.isPresent && device.isLaptopBattery
    )
    readonly property int percentage: batteryAvailable
        ? Math.round(Number(device.percentage || 0) * 100)
        : 0
    readonly property bool charging: batteryAvailable && (
        device.state === UPowerDeviceState.Charging
        || device.state === UPowerDeviceState.PendingCharge
    )
    readonly property bool discharging: batteryAvailable && (
        device.state === UPowerDeviceState.Discharging
        || device.state === UPowerDeviceState.PendingDischarge
    )
    readonly property bool full: batteryAvailable
        && device.state === UPowerDeviceState.FullyCharged
    readonly property real remainingSeconds: charging
        ? Number(device.timeToFull || 0)
        : (discharging ? Number(device.timeToEmpty || 0) : 0)
    readonly property int profile: PowerProfiles.profile

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

    function stateLabel() {
        if (full) return "Fully charged"
        if (charging) return "Charging"
        if (discharging) return "On battery"
        if (device && device.state === UPowerDeviceState.Empty) return "Empty"
        return "Connected"
    }

    function formatDuration(seconds) {
        const totalMinutes = Math.max(0, Math.round(Number(seconds || 0) / 60))
        if (totalMinutes <= 0)
            return "Calculating…"
        const hours = Math.floor(totalMinutes / 60)
        const minutes = totalMinutes % 60
        if (hours > 0)
            return hours + "h " + minutes + "m"
        return minutes + "m"
    }

    function timeLabel() {
        if (remainingSeconds <= 0)
            return full ? "Ready" : "Calculating…"
        return root.formatDuration(remainingSeconds) + (charging ? " to full" : " remaining")
    }

    function profileLabel(profileValue) {
        if (profileValue === PowerProfile.PowerSaver) return "Power saver"
        if (profileValue === PowerProfile.Performance) return "Performance"
        return "Balanced"
    }

    function degradationLabel() {
        if (PowerProfiles.degradationReason === PerformanceDegradationReason.HighTemperature)
            return "Performance is limited because the system is running hot."
        if (PowerProfiles.degradationReason === PerformanceDegradationReason.LapDetected)
            return "Performance is limited while the laptop is detected on your lap."
        return ""
    }

    function holdsLabel() {
        const holds = PowerProfiles.holds || []
        if (holds.length === 0)
            return ""
        const hold = holds[0]
        const application = String(hold.applicationId || "An application")
        const reason = String(hold.reason || "requested this power mode")
        return application + " · " + reason
    }

    function setProfile(profileValue) {
        if (profileValue === PowerProfile.Performance && !PowerProfiles.hasPerformanceProfile)
            return
        PowerProfiles.profile = profileValue
    }

    visible: batteryAvailable
    icon: batteryIcon()
    label: full ? "Full" : percentage + "%"
    tooltip: stateLabel() + " · " + percentage + "%"
        + (remainingSeconds > 0 ? "\n" + timeLabel() : "")
        + "\n" + profileLabel(profile)
    attention: !charging && percentage <= 15
    active: charging || batteryPanel.open

    onPressed: button => {
        if (button === Qt.LeftButton) {
            root.bar.hideTooltip(root)
            batteryPanel.open = !batteryPanel.open
        }
    }

    ControlPopup {
        id: batteryPanel
        bar: root.bar
        theme: root.theme
        anchorItem: root
        panelWidth: 390

        ControlPanelHeader {
            theme: root.theme
            icon: root.batteryIcon()
            title: "BATTERY"
            subtitle: root.stateLabel() + " · " + root.timeLabel()
        }

        ControlDivider { theme: root.theme }

        ApplicationSummary {
            theme: root.theme
            metrics: [
                {
                    "label": "CHARGE",
                    "value": root.percentage + "%",
                    "active": root.charging,
                    "attention": !root.charging && root.percentage <= 15
                },
                {
                    "label": "HEALTH",
                    "value": root.device && root.device.healthSupported
                        ? Math.round(Number(root.device.healthPercentage || 0)) + "%"
                        : "—",
                    "attention": root.device && root.device.healthSupported
                        && Number(root.device.healthPercentage || 100) < 70
                },
                {
                    "label": "RATE",
                    "value": root.device && Number(root.device.changeRate || 0) !== 0
                        ? Math.abs(Number(root.device.changeRate)).toFixed(1) + " W"
                        : "—"
                }
            ]
        }

        TelemetryGauge {
            theme: root.theme
            icon: root.batteryIcon()
            label: root.charging ? "CHARGE PROGRESS" : "ENERGY REMAINING"
            value: root.percentage
            valueText: root.percentage + "%"
            attention: !root.charging && root.percentage <= 15
        }

        ApplicationSummary {
            theme: root.theme
            metrics: [
                {
                    "label": root.charging ? "TIME TO FULL" : "TIME LEFT",
                    "value": root.remainingSeconds > 0
                        ? root.formatDuration(root.remainingSeconds)
                        : "—"
                },
                {
                    "label": "ENERGY",
                    "value": root.device
                        ? Number(root.device.energy || 0).toFixed(1) + " Wh"
                        : "—"
                },
                {
                    "label": "CAPACITY",
                    "value": root.device
                        ? Number(root.device.energyCapacity || 0).toFixed(1) + " Wh"
                        : "—"
                }
            ]
        }

        ControlDivider { theme: root.theme }

        ControlSectionLabel {
            theme: root.theme
            text: "POWER MODE"
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            ControlChoice {
                Layout.fillWidth: true
                theme: root.theme
                text: "Saver"
                selected: root.profile === PowerProfile.PowerSaver
                onPressed: root.setProfile(PowerProfile.PowerSaver)
            }

            ControlChoice {
                Layout.fillWidth: true
                theme: root.theme
                text: "Balanced"
                selected: root.profile === PowerProfile.Balanced
                onPressed: root.setProfile(PowerProfile.Balanced)
            }

            ControlChoice {
                Layout.fillWidth: true
                theme: root.theme
                text: "Performance"
                enabled: PowerProfiles.hasPerformanceProfile
                selected: root.profile === PowerProfile.Performance
                onPressed: root.setProfile(PowerProfile.Performance)
            }
        }

        Text {
            visible: root.degradationLabel() !== ""
            Layout.fillWidth: true
            text: root.degradationLabel()
            color: root.theme.warning
            wrapMode: Text.Wrap
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.microTextSize
            renderType: Text.NativeRendering
        }

        Text {
            visible: root.holdsLabel() !== ""
            Layout.fillWidth: true
            text: "Profile hold · " + root.holdsLabel()
            color: root.theme.textMuted
            elide: Text.ElideRight
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.microTextSize
            renderType: Text.NativeRendering
        }
    }
}
