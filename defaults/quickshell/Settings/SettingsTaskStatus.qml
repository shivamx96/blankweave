import QtQuick
import QtQuick.Layouts
ColumnLayout {
    id: root
    required property var theme
    required property var backend
    property string targetKey: ""
    property bool showActionError: true
    visible: !targetKey || Boolean(backend && backend.feedbackTarget === targetKey)
    SettingsResult {
        Layout.fillWidth: true
        theme: root.theme
        message: root.backend ? root.backend.error : ""
        detail: root.backend && root.backend.errorDetail ? root.backend.errorDetail : ""
        cancelled: Boolean(root.backend && root.backend.cancelled)
        visible: root.showActionError && message !== ""
    }
    Text {
        Layout.fillWidth: true
        text: !root.backend ? "Unavailable." : root.backend.notice ? root.backend.notice : !root.backend.ready ? "Loading…" : root.backend.data.message || ""
        visible: text !== ""
        textFormat: Text.PlainText
        color: root.theme.textMuted
        font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap
    }
    SettingsButton { theme: root.theme; text: "Refresh"; enabled: root.backend && !root.backend.busy; onClicked: root.backend.refresh(true) }
}
