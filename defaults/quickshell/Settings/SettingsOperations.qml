pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var theme
    required property string settingId
    required property var backend
    property var editing: null
    property var values: ({})
    property string revision: ""
    readonly property var operations: backend && backend.ready ? backend.data.actions || [] : []
    readonly property var job: backend && backend.ready ? backend.data.job || null : null
    spacing: 10
    function begin(operation) {
        editing = JSON.parse(JSON.stringify(operation))
        revision = backend.data.revision
        let initial = {}
        for (const field of editing.fields) initial[field.key] = field.value
        values = initial
    }
    function submit() {
        backend.apply(Object.assign({}, values, {action: editing.key, confirmed: true}), revision)
        editing = null; values = ({})
    }
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
                Text {
                    text: formField.modelData.label; textFormat: Text.PlainText
                    color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                }
                SettingsTextField {
                    theme: root.theme
                    Layout.fillWidth: true
                    visible: formField.modelData.options.length === 0 && !formField.modelData.multiline
                    text: formField.modelData.value
                    echoMode: formField.modelData.secret ? TextInput.Password : TextInput.Normal
                    Accessible.name: formField.modelData.label
                    onTextEdited: root.values[formField.modelData.key] = text
                }
                SettingsTextArea {
                    theme: root.theme
                    Layout.fillWidth: true
                    Layout.preferredHeight: 90
                    visible: Boolean(formField.modelData.multiline)
                    text: formField.modelData.value
                    Accessible.name: formField.modelData.label
                    wrapMode: TextEdit.WrapAnywhere
                    onTextChanged: if (visible) root.values[formField.modelData.key] = text
                }
                SettingsComboBox {
                    objectName: "operationFieldChoice"
                    theme: root.theme
                    Layout.fillWidth: true
                    visible: formField.modelData.options.length > 0
                    model: formField.modelData.options; textRole: "label"; valueRole: "value"
                    currentIndex: Math.max(0, formField.modelData.options.findIndex(option => option.value === formField.modelData.value))
                    Accessible.name: formField.modelData.label
                    onActivated: root.values[formField.modelData.key] = currentValue
                }
            }
        }
        Text {
            Layout.fillWidth: true
            text: root.editing ? root.editing.confirm : ""
            visible: text !== ""; textFormat: Text.PlainText; wrapMode: Text.WordWrap
            color: root.theme.warning; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
        }
        RowLayout {
            SettingsButton { theme: root.theme; text: root.editing ? root.editing.label : "Apply"; enabled: root.backend && root.backend.writable; onClicked: root.submit() }
            SettingsButton { theme: root.theme; text: "Cancel"; onClicked: { root.editing = null; root.values = ({}) } }
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
