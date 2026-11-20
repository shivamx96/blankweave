pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var theme
    required property var setting
    property var access: null
    signal copyRequested(string text)
    readonly property string file: setting.file || ""
    readonly property var entry: access && access.files && access.files[file] ? access.files[file] : null
    readonly property var overrides: access && access.overrides ? access.overrides[setting.id] || [] : []
    visible: Boolean(file || setting.store || overrides.length)
    spacing: theme.spacing("labelGap")
    Flow {
        Layout.fillWidth: true
        visible: Boolean(root.file || root.setting.store)
        spacing: root.theme.spacing("sm")
        Text {
            objectName: "settingsStorage_" + root.setting.id
            width: Math.min(implicitWidth, parent.width)
            visible: Boolean(root.file || root.setting.store)
            text: root.file ? "Stored in " + (root.entry ? root.entry.display : root.file) + (root.setting.store ? " · " + root.setting.store : "") : "Stored in " + (root.setting.store || "")
            textFormat: Text.PlainText
            color: root.theme.textMuted
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.smallTextSize
            wrapMode: Text.WrapAnywhere
        }
        SettingsButton {
            objectName: "settingsCopyPath_" + root.setting.id
            theme: root.theme
            text: "Copy path"
            visible: Boolean(root.file)
            enabled: root.entry !== null
            onClicked: root.copyRequested(root.entry.path)
        }
        SettingsButton {
            objectName: "settingsOpenFolder_" + root.setting.id
            theme: root.theme
            text: "Open folder"
            visible: Boolean(root.entry && root.entry.exists)
            onClicked: root.access.openFolder(root.file)
        }
    }
    Repeater {
        model: root.overrides
        Text {
            required property var modelData
            Layout.fillWidth: true
            text: "Personal override: " + modelData.display
            textFormat: Text.PlainText
            color: root.theme.textMuted
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.smallTextSize
            wrapMode: Text.WrapAnywhere
        }
    }
}
