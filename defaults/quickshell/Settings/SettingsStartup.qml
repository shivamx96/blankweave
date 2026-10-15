pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
ColumnLayout {
    id: root
    required property var theme
    required property var backend
    spacing: 10
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
                property var entry: parent.modelData
                SettingsButton { theme: root.theme; text: parent.entry.enabled ? "Disable" : "Enable"; enabled: root.backend.writable && parent.entry.writable; onClicked: root.backend.apply({action: "enable", id: parent.entry.id, enabled: !parent.entry.enabled}) }
                SettingsButton { theme: root.theme; text: "Use system entry"; visible: parent.entry.reset; enabled: root.backend.writable; onClicked: root.backend.apply({action: "reset", id: parent.entry.id}) }
            }
        }
    }
    Text {
        visible: root.backend && root.backend.ready && root.backend.data.rows.length === 0
        text: "No XDG startup applications found."
        color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
    }
    SettingsTaskStatus { theme: root.theme; backend: root.backend }
}
