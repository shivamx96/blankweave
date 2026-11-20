pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../Components"
ColumnLayout {
    id: root
    required property var theme
    required property var backend
    spacing: root.theme.spacing("lg")
    ControlTextField { id: name; theme: root.theme; Layout.fillWidth: true; placeholderText: "Application name"; onTextEdited: { if (root.backend && typeof root.backend.clearOutcome === "function") root.backend.clearOutcome("create") } Accessible.name: "Web app name" }
    ControlTextField { id: url; theme: root.theme; Layout.fillWidth: true; placeholderText: "https://example.com"; onTextEdited: { if (root.backend && typeof root.backend.clearOutcome === "function") root.backend.clearOutcome("create") } Accessible.name: "Web app URL" }
    SettingsButton { theme: root.theme; text: "Add web app"; enabled: root.backend && root.backend.writable && root.backend.data.browser && name.text.trim() !== "" && url.text.trim() !== ""; onClicked: root.backend.apply({action: "create", name: name.text, url: url.text.trim()}) }
    SettingsActionResult { theme: root.theme; backend: root.backend; actionKey: "create" }
    Repeater {
        model: root.backend && root.backend.ready ? root.backend.data.rows : []
        delegate: ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            RowLayout {
                Layout.fillWidth: true
                property var modelData: parent.modelData
                Text { Layout.fillWidth: true; text: parent.modelData.name + " · " + parent.modelData.origin + "\n" + parent.modelData.url; textFormat: Text.PlainText; color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WrapAnywhere }
                SettingsConfirmButton { theme: root.theme; actionText: "Remove"; confirmText: "Remove “" + parent.modelData.name + "”"; targetIdentity: parent.modelData.id + root.backend.data.revision; enabled: root.backend.writable && parent.modelData.removable; onConfirmed: root.backend.apply({action: "remove", id: parent.modelData.id}, root.backend.data.revision) }
            }
            SettingsActionResult { theme: root.theme; backend: root.backend; actionKey: "remove"; targetKey: parent.modelData.id }
        }
    }
    SettingsTaskStatus { showActionError: false; theme: root.theme; backend: root.backend }
}
