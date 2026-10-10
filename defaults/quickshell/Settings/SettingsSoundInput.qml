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
    readonly property var inputs: backend && backend.inputs ? backend.inputs : []
    property var menuInputs: []
    property bool selectingFromMenu: false
    readonly property var choices: selectingFromMenu ? menuInputs : inputs
    readonly property int selectedIndex: backend ? choices.findIndex(row => row.key === backend.inputKey) : -1
    spacing: 12

    SettingsComboBox {
        id: device
        objectName: "soundInputDevice"
        Layout.fillWidth: true
        theme: root.theme
        model: root.choices.map(row => row.label)
        currentIndex: root.selectedIndex
        displayText: currentIndex < 0 ? "Choose input…" : currentText
        enabled: root.connected && root.inputs.length > 0
        Accessible.name: "Input device"
        onActivated: index => {
            const row = root.choices[index]
            if (row) root.backend.selectInput(row.key)
            currentIndex = Qt.binding(() => root.selectedIndex)
        }
    }
    Connections {
        target: device.popup
        function onAboutToShow() {
            root.menuInputs = root.inputs.slice()
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
            sliderName: "soundInputVolume"
            volumeLabel: "Microphone gain"
        }
        SettingsButton {
            objectName: "soundInputMute"
            theme: root.theme
            text: root.available && root.backend.muted ? "Unmute" : "Mute"
            enabled: root.available
            Accessible.name: root.available && root.backend.muted ? "Unmute microphone" : "Mute microphone"
            onClicked: root.backend.setInputMuted(!root.backend.muted)
        }
    }
    Text {
        Layout.fillWidth: true
        objectName: "soundInputStatus"
        text: root.backend && root.backend.notice ? root.backend.notice : "Connecting to the audio service…"
        textFormat: Text.PlainText
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        text: "Above 100% amplifies the microphone and may cause distortion."
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    RowLayout {
        Layout.fillWidth: true
        Rectangle {
            objectName: "soundInputLevel"
            Layout.fillWidth: true
            Layout.preferredHeight: 8
            color: root.theme.divider
            readonly property real level: root.backend ? root.backend.level : 0
            Accessible.role: Accessible.ProgressBar
            Accessible.name: "Microphone signal level"
            Accessible.description: root.backend ? root.backend.levelNotice : "Microphone signal unavailable"
            Rectangle {
                width: parent.width * parent.level
                height: parent.height
                color: parent.level >= 0.95 ? root.theme.warning : root.theme.accent
            }
        }
        Text {
            Layout.preferredWidth: 46
            text: root.backend && root.backend.levelReady ? Math.round(root.backend.level * 100) + "%" : "—"
            color: root.theme.textMuted
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.smallTextSize
            horizontalAlignment: Text.AlignRight
        }
    }
    Text {
        Layout.fillWidth: true
        objectName: "soundInputLevelStatus"
        text: root.backend ? root.backend.levelNotice : "Microphone signal unavailable"
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        text: "The meter listens only while these controls are visible. No audio is saved."
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
}
