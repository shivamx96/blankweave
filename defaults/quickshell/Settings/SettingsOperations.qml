pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "OperationActions.js" as Actions

ColumnLayout {
    id: root
    required property var theme
    required property string settingId
    required property var backend
    signal settingRequested(string settingId)
    signal copyRequested(string text)
    readonly property var draft: backend ? backend.draft : null
    readonly property var editing: draft ? draft.editing : null
    readonly property var values: draft ? draft.values : ({})
    readonly property var operations: backend && backend.ready ? backend.data.actions || [] : []
    readonly property var primaryAction: Actions.primary(settingId, operations)
    readonly property var secondaryActions: operations.filter(action => !primaryAction || action.key !== primaryAction.key)
    readonly property bool canOperate: backend && backend.writable && draft && !draft.pending
    readonly property bool operationBusy: Boolean((backend && (backend.writing || backend.data.writable === false)) || (draft && draft.pending))
    onOperationBusyChanged: if (operationBusy) actionMenu.close()
    readonly property var job: backend && backend.ready ? backend.data.job || null : null
    spacing: 10
    function begin(operation) { draft.begin(operation) }
    function submit() { draft.submit() }
    function activate(operation, capturedRevision) {
        if (!canOperate || editing !== null) return
        draft.begin(operation)
        draft.revision = capturedRevision
        if (!draft.stale && Actions.direct(settingId, operation)) draft.submit()
    }
    Component.onDestruction: if (draft) draft.clearSecrets()
    onVisibleChanged: if (!visible) { actionMenu.close(); if (draft) draft.clearSecrets() }
    Repeater {
        model: root.backend && root.backend.ready ? root.backend.data.notices || [] : []
        delegate: ColumnLayout {
            id: guidance
            required property var modelData
            Layout.fillWidth: true
            spacing: 6
            Text {
                Layout.fillWidth: true
                text: guidance.modelData.title
                textFormat: Text.PlainText; wrapMode: Text.WordWrap
                color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
                font.weight: Font.DemiBold
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }
            Text {
                Layout.fillWidth: true
                text: guidance.modelData.nextStep
                textFormat: Text.PlainText; wrapMode: Text.WordWrap
                color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
            }
            SettingsButton {
                objectName: "capabilityNextStep"
                theme: root.theme
                visible: ["backup", "installed"].includes(guidance.modelData.target)
                text: guidance.modelData.target === "backup" ? "Open Scheduled file backups" : "Open Installed applications"
                onClicked: root.settingRequested(guidance.modelData.target)
            }
        }
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
    Flow {
        Layout.fillWidth: true
        spacing: 8
        visible: root.operations.length > 0 && root.editing === null
        SettingsButton {
            objectName: "primaryOperation"
            theme: root.theme
            text: Actions.label(root.settingId, root.primaryAction)
            visible: root.primaryAction !== null
            enabled: root.canOperate
            width: Math.min(implicitWidth, parent.width)
            onClicked: root.activate(root.primaryAction, root.backend.data.revision)
        }
        SettingsButton {
            id: moreButton
            objectName: "moreOperations"
            theme: root.theme
            text: root.primaryAction ? "More actions ▾" : "Actions ▾"
            Accessible.name: "More actions"
            visible: root.secondaryActions.length > 0
            enabled: root.canOperate
            width: Math.min(implicitWidth, parent.width)
            onClicked: {
                actionMenu.entries = root.secondaryActions.map(action => ({
                    action: JSON.parse(JSON.stringify(action)),
                    label: Actions.label(root.settingId, action),
                    revision: root.backend.data.revision
                }))
                actionMenu.popup()
            }
            SettingsActionMenu {
                id: actionMenu
                objectName: "operationActionsMenu"
                theme: root.theme
                enabled: root.canOperate
                width: Math.min(300, root.width)
                y: moreButton.height + 4
                onChosen: entry => root.activate(entry.action, entry.revision)
            }
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
    SettingsJobReport {
        Layout.fillWidth: true
        theme: root.theme
        job: root.job
        visible: root.job !== null && root.backend.dismissedJobId !== root.job.id
        onCopyRequested: text => root.copyRequested(text)
        onDismissRequested: id => root.backend.dismissedJobId = id
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
