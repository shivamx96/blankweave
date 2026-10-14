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
    spacing: 10
    Text {
        Layout.fillWidth: true
        text: root.settingId === "dnd" ? ((root.backend && root.backend.data.paused) ? "Notifications are paused." : "Notifications are enabled.") + ((root.backend && root.backend.data.quiet) ? " Quiet hours are active." : "") : "Apps seen in notification history. Muted popups remain in history; changes apply to new notifications."
        color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap
    }
    SettingsButton {
        visible: root.settingId === "dnd"
        theme: root.theme; text: root.policy.manual ? "Turn off manual DND" : "Turn on manual DND"
        enabled: root.backend && root.backend.writable
        onClicked: root.backend.apply({action: "manual", value: !root.policy.manual})
    }
    RowLayout {
        visible: root.settingId === "dnd"
        Layout.fillWidth: true
        ControlTextField { id: start; theme: root.theme; Layout.fillWidth: true; text: root.policy.start; placeholderText: "Start HH:MM"; Accessible.name: "Quiet hours start" }
        ControlTextField { id: end; theme: root.theme; Layout.fillWidth: true; text: root.policy.end; placeholderText: "End HH:MM"; Accessible.name: "Quiet hours end" }
    }
    RowLayout {
        visible: root.settingId === "dnd"
        SettingsButton { theme: root.theme; text: "Save quiet hours"; enabled: root.backend && root.backend.writable; onClicked: root.backend.apply({action: "schedule", enabled: true, start: start.text, end: end.text}) }
        SettingsButton { theme: root.theme; text: "Disable schedule"; enabled: root.backend && root.backend.writable && root.policy.schedule; onClicked: root.backend.apply({action: "schedule", enabled: false, start: root.policy.start, end: root.policy.end}) }
    }
    Text {
        visible: root.settingId === "dnd"
        Layout.fillWidth: true
        text: "Daily local time, including overnight ranges. " + (root.policy.schedule ? "Schedule enabled." : "Schedule disabled.") + " Quiet hours continue while Settings is closed. Turn off both the schedule and manual DND to resume notifications."
        color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap
    }
    Repeater {
        model: root.settingId === "notifications" && root.backend && root.backend.ready ? root.backend.data.apps : []
        delegate: RowLayout {
            required property string modelData
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: parent.modelData; textFormat: Text.PlainText; color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WrapAnywhere }
            SettingsButton {
                property string app: parent.modelData
                theme: root.theme; text: root.policy.blocked.includes(app) ? "Allow popups" : "Mute popups"
                enabled: root.backend && root.backend.writable
                onClicked: root.backend.apply({action: "app", app: app, blocked: !root.policy.blocked.includes(app)})
            }
        }
    }
    SettingsTaskStatus { theme: root.theme; backend: root.backend }
}
