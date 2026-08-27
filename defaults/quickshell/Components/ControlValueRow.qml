import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root

    required property var theme
    property string icon: ""
    property real from: 0
    property real to: 100
    property real value: 0
    property real stepSize: 1
    property string valueText: Math.round(value) + "%"
    readonly property alias pressed: control.pressed

    signal valueMoved(real value)

    Layout.fillWidth: true
    spacing: 10

    Text {
        visible: root.icon !== ""
        text: root.icon
        color: root.theme.accentBright
        font.family: root.theme.iconFontFamily
        font.pixelSize: root.theme.controlIconSize
        renderType: Text.NativeRendering
    }

    ControlSlider {
        id: control
        theme: root.theme
        Layout.fillWidth: true
        from: root.from
        to: root.to
        value: root.value
        stepSize: root.stepSize
        onMoved: root.valueMoved(value)
    }

    Text {
        Layout.preferredWidth: 42
        horizontalAlignment: Text.AlignRight
        text: root.valueText
        color: root.theme.text
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.textSize
        font.weight: Font.DemiBold
        renderType: Text.NativeRendering
    }
}
