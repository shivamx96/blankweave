pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
ColumnLayout {
    id: root
    required property var theme
    required property var backend
    required property string settingId
    readonly property var report: backend && backend.ready ? backend.data.report : null
    spacing: 10
    Repeater {
        model: root.settingId === "about" && root.backend && root.backend.ready ? root.backend.data.details : []
        delegate: Text {
            required property var modelData
            Layout.fillWidth: true
            text: modelData.label + ": " + modelData.value
            textFormat: Text.PlainText; color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WrapAnywhere
        }
    }
    SettingsButton {
        visible: root.settingId === "diagnostics"
        theme: root.theme; text: root.backend && root.backend.writing ? "Running health checks…" : "Run health checks"
        enabled: root.backend && root.backend.writable && root.backend.data.available
        onClicked: root.backend.apply({action: "diagnose"})
    }
    Text {
        visible: root.settingId === "diagnostics"
        Layout.fillWidth: true
        text: root.report ? "Last run: " + root.report.time + (root.report.code === 0 ? " · Completed" : " · Findings or command errors (exit " + root.report.code + ")") : "No diagnostics report yet."
        color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap
    }
    Rectangle {
        visible: root.settingId === "diagnostics" && root.report !== null
        Layout.fillWidth: true; Layout.preferredHeight: 360
        color: root.theme.surface; border.color: root.theme.outline
        Flickable {
            anchors.fill: parent; anchors.margins: 12
            contentWidth: width; contentHeight: reportText.height
            clip: true
            TextEdit {
                id: reportText
                width: parent.width
                text: root.report ? root.report.text : ""
                readOnly: true; selectByMouse: true; textFormat: TextEdit.PlainText; wrapMode: TextEdit.WrapAnywhere
                color: root.theme.text; selectionColor: root.theme.accent; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
            }
        }
    }
    SettingsButton { visible: root.settingId === "diagnostics" && root.report !== null; theme: root.theme; text: "Copy report"; onClicked: { reportText.selectAll(); reportText.copy(); reportText.deselect() } }
    SettingsTaskStatus { theme: root.theme; backend: root.backend }
}
