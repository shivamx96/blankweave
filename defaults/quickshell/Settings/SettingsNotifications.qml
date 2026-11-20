pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../Components"
ColumnLayout {
    id: root
    required property var theme
    required property var backend
    required property string settingId
    readonly property var policy: backend && backend.ready ? backend.data.policy : ({manual: false, schedule: false, start: "22:00", end: "08:00", blocked: []})
    function clearScheduleOutcome() {
        if (backend && typeof backend.clearOutcome === "function") {
            backend.clearOutcome("schedule")
            backend.clearOutcome("schedule-toggle")
        }
    }
    spacing: root.theme.spacing("lg")
    Text {
        Layout.fillWidth: true
        text: root.settingId === "dnd" ? ((root.backend && root.backend.data.paused) ? "Notifications are paused; critical alerts still appear." : "Notifications are enabled.") + ((root.backend && root.backend.data.quiet) ? " Quiet hours are active." : "") : "Apps seen in notification history. Muted popups remain in history; changes apply to new notifications."
        color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap
    }
    SettingsSwitchRow {
        visible: root.settingId === "dnd"
        theme: root.theme; checked: Boolean(root.backend && root.backend.data.paused); busy: Boolean(root.backend && root.backend.busy); text: "Do not disturb"
        enabled: root.backend && root.backend.writable
        onClicked: root.backend.apply({action: "manual", value: !root.backend.data.paused})
    }
    SettingsActionResult { theme: root.theme; backend: root.backend; actionKey: "manual"; visible: root.settingId === "dnd" && outcome !== null }
    SettingsSwitchRow {
        visible: root.settingId === "dnd"
        theme: root.theme; text: "Quiet hours"; checked: root.policy.schedule
        busy: Boolean(root.backend && root.backend.busy)
        enabled: root.backend && root.backend.writable
        onClicked: root.backend.apply({action: "schedule", enabled: !root.policy.schedule, start: start.text, end: end.text}, undefined, "schedule-toggle")
    }
    SettingsActionResult { theme: root.theme; backend: root.backend; actionKey: "schedule-toggle"; visible: root.settingId === "dnd" && outcome !== null }
    RowLayout {
        visible: root.settingId === "dnd"
        Layout.fillWidth: true
        ControlTextField { id: start; theme: root.theme; Layout.fillWidth: true; text: root.policy.start; placeholderText: "Start HH:MM"; onTextEdited: { root.clearScheduleOutcome() } Accessible.name: "Quiet hours start" }
        ControlTextField { id: end; theme: root.theme; Layout.fillWidth: true; text: root.policy.end; placeholderText: "End HH:MM"; onTextEdited: { root.clearScheduleOutcome() } Accessible.name: "Quiet hours end" }
    }
    RowLayout {
        visible: root.settingId === "dnd"
        SettingsButton { theme: root.theme; text: "Save quiet hours"; enabled: root.backend && root.backend.writable; onClicked: root.backend.apply({action: "schedule", enabled: root.policy.schedule, start: start.text, end: end.text}) }
    }
    SettingsActionResult { theme: root.theme; backend: root.backend; actionKey: "schedule"; visible: root.settingId === "dnd" && outcome !== null }
    Text {
        visible: root.settingId === "dnd"
        Layout.fillWidth: true
        text: "Daily local time, including overnight ranges. " + (root.policy.schedule ? "Schedule enabled." : "Schedule disabled.") + " Quiet hours continue while Settings is closed. Manual changes override the current quiet-hours window. The next scheduled window resumes normal scheduling."
        color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap
    }
    Repeater {
        model: root.settingId === "notifications" && root.backend && root.backend.ready ? root.backend.data.apps : []
        delegate: ColumnLayout {
            required property string modelData
            Layout.fillWidth: true
            RowLayout {
                Layout.fillWidth: true
                property string modelData: parent.modelData
                Text { Layout.fillWidth: true; text: parent.modelData; textFormat: Text.PlainText; color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WrapAnywhere }
                SettingsSwitchRow {
                    property string app: parent.modelData
                    theme: root.theme; checked: root.policy.blocked.includes(app); busy: Boolean(root.backend && root.backend.busy); text: "Mute popups"
                    enabled: root.backend && root.backend.writable
                    onClicked: root.backend.apply({action: "app", app: app, blocked: !root.policy.blocked.includes(app)})
            }
            }
            SettingsActionResult { theme: root.theme; backend: root.backend; actionKey: "app"; targetKey: parent.modelData }
        }
    }
    SettingsTaskStatus { showActionError: false; theme: root.theme; backend: root.backend }
}
