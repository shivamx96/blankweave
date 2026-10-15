pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../Components"
ColumnLayout {
    id: root
    required property var theme
    required property var backend
    property string removeId: ""
    property string removeRevision: ""
    property string removeName: ""
    spacing: 10
    ControlTextField { id: name; theme: root.theme; Layout.fillWidth: true; placeholderText: "Application name"; Accessible.name: "Web app name" }
    ControlTextField { id: url; theme: root.theme; Layout.fillWidth: true; placeholderText: "https://example.com"; Accessible.name: "Web app URL" }
    SettingsButton { theme: root.theme; text: "Add web app"; enabled: root.backend && root.backend.writable && root.backend.data.browser && name.text.trim() !== "" && url.text.trim() !== ""; onClicked: root.backend.apply({action: "create", name: name.text, url: url.text.trim()}) }
    Repeater {
        model: root.backend && root.backend.ready ? root.backend.data.rows : []
        delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: parent.modelData.name + " · " + parent.modelData.origin + "\n" + parent.modelData.url; textFormat: Text.PlainText; color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WrapAnywhere }
            SettingsButton { theme: root.theme; text: "Remove…"; enabled: root.backend.writable && parent.modelData.removable; onClicked: { root.removeId = parent.modelData.id; root.removeName = parent.modelData.name; root.removeRevision = root.backend.data.revision } }
        }
    }
    Text { Layout.fillWidth: true; visible: root.removeId !== ""; text: "Remove “" + root.removeName + "” from the launcher? Browser data and logins are kept."; textFormat: Text.PlainText; color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap }
    RowLayout {
        visible: root.removeId !== ""
        SettingsButton { theme: root.theme; text: "Remove web app"; enabled: root.backend && root.backend.writable; onClicked: { root.backend.apply({action: "remove", id: root.removeId}, root.removeRevision); root.removeId = "" } }
        SettingsButton { theme: root.theme; text: "Cancel"; onClicked: root.removeId = "" }
    }
    SettingsTaskStatus { theme: root.theme; backend: root.backend }
}
