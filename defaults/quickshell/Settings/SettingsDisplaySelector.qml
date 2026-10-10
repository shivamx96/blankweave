import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var theme
    required property var backend
    spacing: 10

    RowLayout {
        Layout.fillWidth: true
        Text {
            objectName: "displayStatus"
            Layout.fillWidth: true
            text: root.backend.error || (!root.backend.loaded ? "Loading displays…"
                : root.backend.monitors.length === 0 ? "No connected displays."
                : root.backend.previewPending === true ? "Confirm or revert the display mode."
                : root.backend.busy ? "Updating displays…" : "Choose a display to adjust.")
            color: root.backend.error ? root.theme.warning : root.theme.textMuted
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.smallTextSize
            wrapMode: Text.WordWrap
        }
        SettingsButton {
            theme: root.theme
            text: "Refresh"
            enabled: !root.backend.busy
            onClicked: root.backend.refresh()
        }
    }
    SettingsComboBox {
        objectName: "settingsDisplaySelector"
        Layout.fillWidth: true
        theme: root.theme
        model: root.backend.monitors.map(row => root.backend.label(row))
        currentIndex: root.backend.monitors.findIndex(row => row.name === root.backend.selectedConnector)
        enabled: root.backend.ready && root.backend.canSelect
        Accessible.name: "Display"
        onActivated: index => {
            root.backend.selectDisplay(index)
            currentIndex = Qt.binding(() => root.backend.monitors.findIndex(row => row.name === root.backend.selectedConnector))
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.backend.previewPending === true
        spacing: 8
        Text {
            Layout.fillWidth: true
            text: root.backend.previewMessage || ""
            color: root.theme.warning
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.smallTextSize
            wrapMode: Text.WordWrap
        }
        RowLayout {
            SettingsButton {
                objectName: "keepDisplayMode"
                theme: root.theme
                text: "Keep changes"
                enabled: !root.backend.applying && root.backend.previewSeconds > 0
                onClicked: root.backend.finishPreview(true)
            }
            SettingsButton {
                objectName: "revertDisplayMode"
                theme: root.theme
                text: "Revert"
                enabled: !root.backend.applying
                onClicked: root.backend.finishPreview(false)
            }
        }
    }
    Text {
        objectName: "displayDetails"
        Layout.fillWidth: true
        text: root.backend.details
        visible: text !== ""
        color: root.theme.text
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        text: root.backend.savedScaleNotice
        visible: text !== ""
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
}
