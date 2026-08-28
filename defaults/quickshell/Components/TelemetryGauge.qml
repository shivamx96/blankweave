import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    required property var theme
    property string icon: ""
    property string label: ""
    property real value: 0
    property real maximum: 100
    property string valueText: Math.round(value) + "%"
    property int segments: 24
    property bool attention: false
    readonly property real progress: maximum > 0
        ? Math.max(0, Math.min(1, value / maximum))
        : 0
    readonly property color activeColor: attention ? theme.critical : theme.accentBright

    Layout.fillWidth: true
    spacing: 6

    RowLayout {
        Layout.fillWidth: true
        spacing: 7

        Text {
            visible: root.icon !== ""
            text: root.icon
            color: root.activeColor
            font.family: root.theme.iconFontFamily
            font.pixelSize: root.theme.controlIconSize
            renderType: Text.NativeRendering
        }

        Text {
            Layout.fillWidth: true
            text: root.label
            color: root.theme.textMuted
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.microTextSize
            font.weight: Font.DemiBold
            font.letterSpacing: 1.05
            renderType: Text.NativeRendering
        }

        Text {
            text: root.valueText
            color: root.attention ? root.theme.critical : root.theme.text
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.textSize
            font.weight: Font.Bold
            renderType: Text.NativeRendering
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 7
        spacing: 2

        Repeater {
            model: root.segments

            Rectangle {
                required property int index

                Layout.fillWidth: true
                Layout.preferredHeight: index % 4 === 3 ? 7 : 5
                color: index < Math.ceil(root.progress * root.segments)
                    ? root.activeColor
                    : root.theme.outline
                opacity: index < Math.ceil(root.progress * root.segments) ? 1 : 0.48

                Behavior on color { ColorAnimation { duration: 140 } }
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }
        }
    }
}
