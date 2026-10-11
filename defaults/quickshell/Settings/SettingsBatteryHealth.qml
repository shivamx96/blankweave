pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var theme
    required property var backend
    readonly property bool ready: backend !== null && backend.ready
    spacing: 12
    function percent(value) { return value === null ? "Unknown" : Math.round(value) + "%" }
    function energy(value) { return value === null ? "Unknown" : value.toFixed(1) + " Wh" }
    function limitDescription(row) {
        if (!row.supported) return "This battery does not expose charge-limit controls."
        if (row.start === null && row.end === null)
            return row.firmware ? "Firmware manages the charge limit; it does not report a fixed percentage."
                : "The system manages the charge limit; threshold percentages are not reported."
        const parts = []
        if (row.start !== null) parts.push("Starts charging below " + row.start + "%")
        if (row.end !== null) parts.push("stops charging at " + row.end + "%")
        return "Configured limits: " + parts.join("; ") + "." + (row.firmware ? " Firmware also manages charging behavior." : "")
    }
    Repeater {
        model: root.ready ? root.backend.batteries : []
        delegate: ColumnLayout {
            id: battery
            required property var modelData
            required property int index
            Layout.fillWidth: true
            spacing: 10
            Rectangle {
                visible: battery.index > 0
                Layout.fillWidth: true
                implicitHeight: 1
                color: root.theme.divider
            }
            Text {
                Layout.fillWidth: true
                text: "Battery " + (battery.index + 1) + " · " + battery.modelData.name
                textFormat: Text.PlainText
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.textSize
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
            }
            Text {
                objectName: "batterySummary_" + battery.index
                Layout.fillWidth: true
                text: battery.modelData.state + " · " + root.percent(battery.modelData.charge) + " charged"
                    + "\nHealth: " + root.percent(battery.modelData.health)
                    + " · Cycles: " + (battery.modelData.cycles === null ? "Unknown" : battery.modelData.cycles)
                    + "\nFull-charge capacity: " + root.energy(battery.modelData.energyFull)
                    + " · Design capacity: " + root.energy(battery.modelData.energyDesign)
                textFormat: Text.PlainText
                color: root.theme.textMuted
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.smallTextSize
                wrapMode: Text.WordWrap
            }
            SettingsButton {
                objectName: "batteryLimit_" + battery.index
                theme: root.theme
                text: !battery.modelData.supported ? "Charge limit unavailable"
                    : battery.modelData.enabled ? "Charge limit: On" : "Charge limit: Off"
                selected: battery.modelData.enabled === true
                enabled: battery.modelData.supported && !root.backend.busy
                onClicked: root.backend.setLimit(battery.modelData, !battery.modelData.enabled)
            }
            Text {
                Layout.fillWidth: true
                text: root.limitDescription(battery.modelData)
                textFormat: Text.PlainText
                color: root.theme.textMuted
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.smallTextSize
                wrapMode: Text.WordWrap
            }
        }
    }
    Text {
        objectName: "batteryHealthStatus"
        Layout.fillWidth: true
        text: root.backend && root.backend.error ? root.backend.error
            : !root.ready ? "Reading battery information…"
            : !root.backend.available ? "Battery information is unavailable. Check that UPower is running."
            : root.backend.batteries.length === 0 ? "No system batteries detected."
            : "Health compares reported full-charge capacity with the original design capacity. Missing readings are shown as unknown. Charge limits use the system’s configured thresholds or firmware policy."
        textFormat: Text.PlainText
        color: root.backend && root.backend.error ? root.theme.critical : root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    SettingsButton {
        objectName: "batteryHealthRefresh"
        theme: root.theme
        text: "Refresh"
        enabled: root.backend !== null && !root.backend.busy
        onClicked: root.backend.refresh(true)
    }
}
