import QtQuick
import QtQuick.Layouts
ColumnLayout {
    id: root
    required property var theme
    required property var backend
    Text {
        Layout.fillWidth: true
        text: !root.backend ? "Unavailable." : root.backend.error || (!root.backend.ready ? "Loading…" : root.backend.data.message || "")
        visible: text !== ""
        textFormat: Text.PlainText
        color: root.backend && root.backend.error ? root.theme.warning : root.theme.textMuted
        font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap
    }
    SettingsButton { theme: root.theme; text: "Refresh"; enabled: root.backend && !root.backend.busy; onClicked: root.backend.refresh(true) }
}
