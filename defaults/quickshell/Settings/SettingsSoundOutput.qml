pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../Components"

ColumnLayout {
    id: root
    required property var theme
    required property var backend
    readonly property bool connected: backend !== null && Boolean(backend.ready)
    readonly property bool available: backend !== null && Boolean(backend.available)
    readonly property var outputs: backend && backend.outputs ? backend.outputs : []
    property var menuOutputs: []
    property bool selectingFromMenu: false
    readonly property var choices: selectingFromMenu ? menuOutputs : outputs
    readonly property int selectedIndex: backend ? choices.findIndex(row => row.key === backend.outputKey) : -1
    spacing: 12

    SettingsComboBox {
        id: device
        objectName: "soundOutputDevice"
        Layout.fillWidth: true
        theme: root.theme
        model: root.choices.map(row => row.label)
        currentIndex: root.selectedIndex
        displayText: currentIndex < 0 ? "Choose output…" : currentText
        enabled: root.connected && root.outputs.length > 0
        Accessible.name: "Output device"
        onActivated: index => {
            const row = root.choices[index]
            if (row) root.backend.selectOutput(row.key)
            currentIndex = Qt.binding(() => root.selectedIndex)
        }
    }
    Connections {
        target: device.popup
        function onAboutToShow() {
            root.menuOutputs = root.outputs.slice()
            root.selectingFromMenu = true
        }
        // Some Qt styles close the popup before emitting activated. Keep the
        // captured rows until that event has finished, including after hotplug.
        function onClosed() { Qt.callLater(() => { if (!device.popup.visible) root.selectingFromMenu = false }) }
    }
    RowLayout {
        Layout.fillWidth: true
        AudioVolumeControl {
            theme: root.theme
            backend: root.backend
        }
        SettingsButton {
            objectName: "soundOutputMute"
            theme: root.theme
            text: root.available && root.backend.muted ? "Unmute" : "Mute"
            enabled: root.available
            Accessible.name: root.available && root.backend.muted ? "Unmute output" : "Mute output"
            onClicked: root.backend.setOutputMuted(!root.backend.muted)
        }
    }
    Text {
        Layout.fillWidth: true
        objectName: "soundOutputStatus"
        text: root.backend && root.backend.notice ? root.backend.notice : "Connecting to the audio service…"
        textFormat: Text.PlainText
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        text: "Above 100% amplifies audio and may cause distortion."
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
}
