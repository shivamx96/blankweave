pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var theme
    required property var backend
    required property string settingId
    readonly property string key: settingId === "motion" ? "reduced_motion" : "high_contrast"
    readonly property bool ready: backend !== null && backend.ready
    property var snapshot: null
    spacing: 10
    SettingsComboBox {
        id: choice
        objectName: "accessibility_" + root.key
        Layout.fillWidth: true
        theme: root.theme
        model: ["Off", "On"]
        currentIndex: root.ready ? (root.backend.saved[root.key] ? 1 : 0) : -1
        enabled: root.ready && root.backend.writable
        Accessible.name: root.settingId === "motion" ? "Reduce motion" : "High contrast"
        onActivated: index => {
            if (index === 0 || index === 1) root.backend.apply(root.key, index === 1, root.snapshot)
            currentIndex = Qt.binding(() => root.ready ? (root.backend.saved[root.key] ? 1 : 0) : -1)
        }
    }
    Connections {
        target: choice.popup
        function onAboutToShow() { root.snapshot = root.backend.snapshot() }
        function onClosed() { Qt.callLater(() => { if (!choice.popup.visible) root.snapshot = null }) }
    }
    Text {
        Layout.fillWidth: true
        text: root.settingId === "motion" ? "Applies to window, shell, and wallpaper transitions. Compatible apps receive the animation preference; some may need reopening."
            : "Uses a high-contrast shell palette in the current color mode. Turning it off restores your chosen theme. Applications must support the desktop contrast preference."
        color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        visible: root.ready && (root.backend.desktop[root.key] !== root.backend.saved[root.key]
            || (root.key === "reduced_motion" && root.backend.desktop.compositor_motion !== root.backend.saved[root.key]))
        text: "Desktop settings differ from this saved preference. Choose On or Off to reapply it. Personal animation overrides may need editing separately."
        color: root.theme.warning; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        text: root.backend === null ? "Accessibility settings unavailable." : root.backend.error || (!root.ready ? "Loading accessibility settings…" : root.backend.message)
        visible: text !== ""
        color: root.backend && root.backend.error ? root.theme.warning : root.theme.textMuted
        font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap
    }
    SettingsButton {
        theme: root.theme; text: "Refresh"
        enabled: root.backend !== null && !root.backend.busy
        onClicked: root.backend.refresh(true)
    }
}
