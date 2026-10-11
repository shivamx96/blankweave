import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../Components"

WidgetFrame {
    id: root

    required property var power
    readonly property bool profileRequested: batteryPanel.open || bar.tooltipTarget === root
    onProfileRequestedChanged: power.setActive(root, profileRequested)
    readonly property string holdsLabel: power.holds.map(hold => (hold.application || "An application") + " · " + hold.reason).join("; ")
    Component.onDestruction: power.setActive(root, false)

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

    visible: batteryAvailable
    icon: batteryIcon()
    label: full ? "Full" : percentage + "%"
    tooltip: stateLabel() + " · " + percentage + "%"
        + (remainingSeconds > 0 ? "\n" + timeLabel() : "")
        + (root.power.ready && root.power.available ? "\n" + root.power.profileName : "")
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
                enabled: root.power.canSelect("power-saver")
                selected: root.power.ready && root.power.profile === "power-saver"
                onPressed: root.power.select("power-saver")
            }

            ControlChoice {
                Layout.fillWidth: true
                theme: root.theme
                text: "Balanced"
                enabled: root.power.canSelect("balanced")
                selected: root.power.ready && root.power.profile === "balanced"
                onPressed: root.power.select("balanced")
            }

            ControlChoice {
                Layout.fillWidth: true
                theme: root.theme
                text: "Performance"
                enabled: root.power.canSelect("performance")
                selected: root.power.ready && root.power.profile === "performance"
                onPressed: root.power.select("performance")
            }
        }

        Text {
            Layout.fillWidth: true
            text: root.power.error || root.power.explanation
            textFormat: Text.PlainText
            color: root.power.error ? root.theme.critical : root.theme.textMuted
            wrapMode: Text.WordWrap
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.microTextSize
        }

        Text {
            Layout.fillWidth: true
            visible: root.power.automaticEnabled || root.power.automaticError !== ""
            text: root.power.automaticError || "Automatic profiles on · choosing a mode turns them off."
            textFormat: Text.PlainText
            color: root.power.automaticError ? root.theme.warning : root.theme.textMuted
            wrapMode: Text.WordWrap
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.microTextSize
        }

        Text {
            visible: root.power.degradation !== ""
            Layout.fillWidth: true
            text: root.power.degradation
            color: root.theme.warning
            wrapMode: Text.Wrap
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.microTextSize
            renderType: Text.NativeRendering
        }

        Text {
            visible: root.holdsLabel !== ""
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: "Profile hold · " + root.holdsLabel
            color: root.theme.textMuted
            elide: Text.ElideRight
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.microTextSize
            renderType: Text.NativeRendering
        }
    }
}
