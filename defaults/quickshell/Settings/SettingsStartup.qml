pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
ColumnLayout {
    id: root
    required property var theme
    required property var backend
    spacing: root.theme.spacing("lg")
    Repeater {
        model: root.backend && root.backend.ready ? root.backend.data.rows : []
        delegate: ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: parent.modelData.name + " · " + parent.modelData.source + " · " + (parent.modelData.enabled ? "Enabled" : "Disabled") + (parent.modelData.reason ? "\n" + parent.modelData.reason : "")
                textFormat: Text.PlainText; color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap
            }
            RowLayout {
                id: entryControls
                property var entry: parent.modelData
                SettingsSwitchRow { theme: root.theme; checked: parent.entry.enabled; busy: Boolean(root.backend && root.backend.busy); text: "Start at sign-in"; enabled: root.backend.writable && parent.entry.writable; onClicked: root.backend.apply({action: "enable", id: parent.entry.id, enabled: !parent.entry.enabled}) }
                SettingsConfirmButton {
                targetIdentity: parent.entry.id + root.backend.data.revision
                theme: root.theme; actionText: "Use system entry"; visible: parent.entry.reset; enabled: root.backend.writable; onConfirmed: root.backend.apply({action: "reset", id: parent.entry.id}) }
            }
            SettingsActionResult { theme: root.theme; backend: root.backend; actionKey: "enable"; targetKey: parent.modelData.id }
            SettingsActionResult { theme: root.theme; backend: root.backend; actionKey: "reset"; targetKey: parent.modelData.id }
        }
    }
    Text {
        visible: root.backend && root.backend.ready && root.backend.data.rows.length === 0
        text: "No XDG startup applications found."
        color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
    }
    SettingsTaskStatus { showActionError: false; theme: root.theme; backend: root.backend }
}
