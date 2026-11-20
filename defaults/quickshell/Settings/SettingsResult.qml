import QtQuick
import QtQuick.Layouts
ColumnLayout {
    id: root
    required property var theme
    property string message: ""
    property string detail: ""
    property bool cancelled: false
    property bool expanded: false
    signal copyRequested(string text)
    onMessageChanged: expanded = false
    Text { objectName: "settingsResultMessage"; Layout.fillWidth: true; text: root.message; textFormat: Text.PlainText; wrapMode: Text.WordWrap; color: root.cancelled ? root.theme.textMuted : root.theme.critical; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; Accessible.name: text }
    SettingsButton { theme: root.theme; visible: root.detail !== ""; text: root.expanded ? "Hide details" : "Show details"; onClicked: root.expanded = !root.expanded }
    TextEdit { id: details; objectName: "settingsResultDetails"; Layout.fillWidth: true; visible: root.expanded; text: root.detail; textFormat: TextEdit.PlainText; readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap; color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize }
    SettingsButton { theme: root.theme; visible: root.expanded; text: "Copy details"; onClicked: { root.copyRequested(root.detail); details.selectAll(); details.copy(); details.deselect(); } }
}
