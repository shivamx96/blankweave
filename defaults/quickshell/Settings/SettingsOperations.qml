pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var theme
    required property string settingId
    required property var backend
    readonly property var draft: backend ? backend.draft : null
    readonly property var editing: draft ? draft.editing : null
    readonly property var values: draft ? draft.values : ({})
    readonly property var operations: backend && backend.ready ? backend.data.actions || [] : []
    readonly property var job: backend && backend.ready ? backend.data.job || null : null
    spacing: 10
    function begin(operation) { draft.begin(operation) }
    function submit() { draft.submit() }
    Component.onDestruction: if (draft) draft.clearSecrets()
    onVisibleChanged: if (!visible && draft) draft.clearSecrets()
    Repeater {
        model: root.backend && root.backend.ready ? root.backend.data.details || [] : []
        delegate: Text {
            required property string modelData
            Layout.fillWidth: true
            text: modelData; textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere
            color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
        }
    }
    RowLayout {
        Layout.fillWidth: true
        visible: root.operations.length > 0 && root.editing === null
        SettingsComboBox {
            id: operationChoice
            objectName: "operationChoice"
            theme: root.theme
            Layout.fillWidth: true
            model: root.operations; textRole: "label"
            Accessible.name: "Operation"
        }
        SettingsButton {
            theme: root.theme; text: "Configure…"
            enabled: root.backend && root.backend.writable && operationChoice.currentIndex >= 0
            onClicked: root.begin(root.operations[operationChoice.currentIndex])
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.editing !== null
        Repeater {
            model: root.editing ? root.editing.fields : []
            delegate: ColumnLayout {
                id: formField
                required property var modelData
                Layout.fillWidth: true
                enabled: !root.draft.pending
                Text {
                    text: formField.modelData.label; textFormat: Text.PlainText
                    color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                }
                SettingsTextField {
                    objectName: "operationField_" + formField.modelData.key
                    theme: root.theme
                    Layout.fillWidth: true
                    visible: formField.modelData.options.length === 0 && !formField.modelData.multiline
                    text: String(root.values[formField.modelData.key] ?? "")
                    echoMode: formField.modelData.secret ? TextInput.Password : TextInput.Normal
                    Accessible.name: formField.modelData.label
                    onTextEdited: root.draft.setValue(formField.modelData.key, text)
                }
                SettingsTextArea {
                    theme: root.theme
                    Layout.fillWidth: true
                    Layout.preferredHeight: 90
                    visible: Boolean(formField.modelData.multiline)
                    text: String(root.values[formField.modelData.key] ?? "")
                    Accessible.name: formField.modelData.label
                    wrapMode: TextEdit.WrapAnywhere
                    onTextChanged: if (visible && text !== root.values[formField.modelData.key]) root.draft.setValue(formField.modelData.key, text)
                }
                SettingsComboBox {
                    objectName: "operationFieldChoice"
                    theme: root.theme
                    Layout.fillWidth: true
                    visible: formField.modelData.options.length > 0
                    model: formField.modelData.options; textRole: "label"; valueRole: "value"
                    currentIndex: Math.max(0, formField.modelData.options.findIndex(option => option.value === root.values[formField.modelData.key]))
                    Accessible.name: formField.modelData.label
                    onActivated: root.draft.setValue(formField.modelData.key, currentValue)
                }
            }
        }
        Text {
            Layout.fillWidth: true
            text: root.editing ? root.editing.confirm : ""
            visible: text !== ""; textFormat: Text.PlainText; wrapMode: Text.WordWrap
            color: root.theme.warning; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
        }
        Text {
            Layout.fillWidth: true
            text: root.draft && root.draft.pending ? "Operation in progress. You can leave this page; your draft stays here until it succeeds."
                : "Your draft is kept while you browse Settings. Cancel discards it."
            color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
            wrapMode: Text.WordWrap
        }
        Text {
            Layout.fillWidth: true
            visible: root.draft && root.draft.secretsCleared && !root.draft.pending
            text: "Password fields were cleared. Re-enter any required passwords before retrying."
            color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
            wrapMode: Text.WordWrap
        }
        Text {
            objectName: "operationFormError"
            Layout.fillWidth: true
            text: root.draft ? root.draft.error : ""
            visible: text !== ""
            textFormat: Text.PlainText; wrapMode: Text.WordWrap
            color: root.theme.warning; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }
        Text {
            Layout.fillWidth: true
            visible: root.draft && root.draft.stale && !root.draft.pending
            text: "Available settings changed. Review the current action and target before submitting again."
            wrapMode: Text.WordWrap
            color: root.theme.warning; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
        }
        RowLayout {
            SettingsButton {
                theme: root.theme
                text: root.draft && root.draft.pending ? "Working…" : root.editing && root.draft && root.draft.error ? "Retry " + root.editing.label : root.editing ? root.editing.label : "Apply"
                enabled: root.backend && root.backend.writable && root.draft && !root.draft.pending && !root.draft.stale
                onClicked: root.submit()
            }
            SettingsButton {
                theme: root.theme; text: "Review current settings"
                visible: root.draft && root.draft.stale && !root.draft.pending
                enabled: root.backend && root.backend.writable
                onClicked: root.draft.review()
            }
            SettingsButton { theme: root.theme; text: "Cancel"; enabled: root.draft && !root.draft.pending; onClicked: root.draft.discard() }
        }
    }
    TextEdit {
        selectionColor: root.theme.accentSurface
        selectedTextColor: root.theme.text
        Layout.fillWidth: true
        visible: root.job !== null
        text: root.job ? root.job.label + " · " + root.job.phase + "\n" + root.job.message : ""
        textFormat: TextEdit.PlainText; readOnly: true; selectByMouse: true; wrapMode: TextEdit.WrapAnywhere
        color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
    }
    SettingsButton {
        theme: root.theme; text: "Cancel operation"
        visible: root.job !== null && root.job.cancellable && ["starting", "running"].includes(root.job.phase)
        enabled: root.backend && !root.backend.busy
        onClicked: {
            // Cancellation is allowed while the provider is otherwise unwritable.
            root.backend.cancelJob(root.job.id)
        }
    }
    SettingsTaskStatus { theme: root.theme; backend: root.backend }
}
