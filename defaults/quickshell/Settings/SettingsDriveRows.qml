pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
ColumnLayout {
    id: root
    required property var theme
    required property var backend
    function run(key) {
        const operation = backend.data.actions.find(a => a.key === key)
        if (operation) { backend.draft.begin(operation); if (!operation.fields.length) backend.draft.submit() }
    }
    Repeater {
        model: root.backend && root.backend.ready ? root.backend.data.drives || [] : []
        delegate: ColumnLayout {
            id: drive
            required property var modelData
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true; wrapMode: Text.WordWrap; textFormat: Text.PlainText
                text: drive.modelData.label + " · " + drive.modelData.size + " · " + drive.modelData.filesystem + " · " + drive.modelData.mountpoint + (drive.modelData.protected ? " · System drive (read-only)" : "")
                color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
            }
            Flow {
                Layout.fillWidth: true; spacing: root.theme.spacing("sm")
                Repeater {
                    model: drive.modelData.commands
                    delegate: ColumnLayout {
                        id: command
                        required property string modelData
                        readonly property string key: modelData + ":" + (modelData === "eject" ? drive.modelData.ejectIdentity : drive.modelData.identity)
                        SettingsConfirmButton {
                            theme: root.theme
                            actionText: command.modelData === "eject" ? "Eject" : command.modelData === "mount" ? "Mount" : command.modelData === "unmount" ? "Unmount" : command.modelData === "unlock" ? "Unlock" : "Lock"
                            confirmText: "Unmount partitions and eject"
                            confirmationRequired: command.modelData === "eject" && drive.modelData.busy
                            targetIdentity: drive.modelData.identity + ":" + root.backend.data.revision
                            enabled: root.backend.writable && !root.backend.draft.pending
                            onConfirmed: root.run(command.key)
                        }
                        SettingsActionResult { theme: root.theme; backend: root.backend; actionKey: command.key }
                    }
                }
            }
        }
    }
}
