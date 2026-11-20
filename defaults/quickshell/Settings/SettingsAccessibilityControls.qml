pragma ComponentBehavior: Bound
import QtQuick
import "LegacyErrors.js" as Errors
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var theme
    required property var backend
    required property string settingId
    readonly property string key: settingId === "motion" ? "reduced_motion" : "high_contrast"
    readonly property bool ready: backend !== null && backend.ready
    property var snapshot: null
    spacing: root.theme.spacing("lg")
    SettingsSwitchRow {
        objectName: "accessibility_" + root.key
        Layout.fillWidth: true
        theme: root.theme
        text: root.settingId === "motion" ? "Reduce motion" : "High contrast"
        checked: root.ready && root.backend.saved[root.key]
        busy: Boolean(root.backend && root.backend.busy)
        error: root.backend ? Errors.message(root.backend.error) : ""
        enabled: root.ready && root.backend.writable
        onClicked: root.backend.apply(root.key, !root.backend.saved[root.key], root.backend.snapshot())
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
        text: root.backend === null ? "Accessibility settings unavailable." : Errors.message(root.backend.error) || (!root.ready ? "Loading accessibility settings…" : root.backend.message)
        visible: text !== ""
        color: root.backend && Errors.message(root.backend.error) ? root.theme.critical : root.theme.textMuted
        font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap
    }
    SettingsButton {
        theme: root.theme; text: "Refresh"
        enabled: root.backend !== null && !root.backend.busy
        onClicked: root.backend.refresh(true)
    }
}
