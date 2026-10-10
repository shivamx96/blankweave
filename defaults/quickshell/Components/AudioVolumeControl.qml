import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root
    required property var theme
    required property var backend
    readonly property bool available: backend !== null && Boolean(backend.available)
    property string sliderName: "soundOutputVolume"
    property string volumeLabel: "Output volume"
    property int dragGeneration: -1
    spacing: 10
    Layout.fillWidth: true

    ControlSlider {
        id: slider
        objectName: root.sliderName
        Layout.fillWidth: true
        theme: root.theme
        from: 0
        to: 150
        stepSize: 1
        value: root.available ? root.backend.volume * 100 : 0
        enabled: root.available
        opacity: enabled ? 1 : 0.45
        Accessible.name: root.volumeLabel
        Accessible.description: "Volume in percent; above 100 percent amplifies audio."
        onPressedChanged: root.dragGeneration = pressed && root.available ? root.backend.generation : -1
        onMoved: {
            if (root.available) root.backend.setVolume(value / 100,
                root.dragGeneration >= 0 ? root.dragGeneration : root.backend.generation)
            // A rejected or cancelled drag must return to the observed value.
            value = Qt.binding(() => root.available ? root.backend.volume * 100 : 0)
        }
    }
    Text {
        Layout.preferredWidth: 46
        text: root.available ? Math.round(root.backend.volume * 100) + "%" : "—"
        color: root.available ? root.theme.text : root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        horizontalAlignment: Text.AlignRight
    }
}
