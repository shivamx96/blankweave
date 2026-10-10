pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var theme
    required property var backend
    readonly property bool writable: backend && backend.ready && !backend.busy && typeof backend.canApply === "function" && backend.canApply("display-presets")
    property string deletingId: ""
    spacing: 12

    RowLayout {
        Layout.fillWidth: true
        TextField {
            id: nameField
            objectName: "displaySetupName"
            Layout.fillWidth: true
            implicitHeight: 36
            placeholderText: "Setup name, e.g. Desk"
            maximumLength: 60
            enabled: root.writable
            color: root.theme.text
            placeholderTextColor: root.theme.textMuted
            selectionColor: root.theme.accentSurface
            selectedTextColor: root.theme.text
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.textSize
            leftPadding: 10
            Accessible.name: "Setup name"
            background: Rectangle {
                color: root.theme.surfaceRaised
                radius: root.theme.widgetRadius
                border.color: nameField.activeFocus ? root.theme.accentBright : root.theme.outline
            }
            onAccepted: if (saveButton.enabled) root.backend.savePreset(text)
        }
        SettingsButton {
            id: saveButton
            objectName: "saveDisplaySetup"
            theme: root.theme
            text: "Save current"
            enabled: root.writable && nameField.text.trim().length > 0
            onClicked: root.backend.savePreset(nameField.text)
        }
    }

    Text {
        Layout.fillWidth: true
        visible: !root.backend || !root.backend.presets || root.backend.presets.length === 0
        text: "No saved setups yet."
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
    }
    Repeater {
        model: root.backend && root.backend.presets ? root.backend.presets : []
        delegate: ColumnLayout {
            id: preset
            required property var modelData
            Layout.fillWidth: true
            spacing: 6
            Text {
                Layout.fillWidth: true
                text: preset.modelData.name
                textFormat: Text.PlainText
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.textSize
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                text: preset.modelData.reason || preset.modelData.summary
                textFormat: Text.PlainText
                color: root.theme.textMuted
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.smallTextSize
                wrapMode: Text.WordWrap
            }
            RowLayout {
                SettingsButton {
                    objectName: "restoreDisplaySetup_" + preset.modelData.id
                    theme: root.theme
                    text: "Restore"
                    enabled: root.writable && preset.modelData.available
                    onClicked: root.backend.restorePreset(preset.modelData.id)
                }
                SettingsButton {
                    objectName: "deleteDisplaySetup_" + preset.modelData.id
                    theme: root.theme
                    text: root.deletingId === preset.modelData.id ? "Confirm delete" : "Delete"
                    enabled: root.writable
                    onClicked: {
                        if (root.deletingId === preset.modelData.id) {
                            root.backend.deletePreset(preset.modelData.id)
                            root.deletingId = ""
                        } else root.deletingId = preset.modelData.id
                    }
                }
                SettingsButton {
                    theme: root.theme
                    text: "Cancel"
                    visible: root.deletingId === preset.modelData.id
                    onClicked: root.deletingId = ""
                }
            }
        }
    }
}
