import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    required property var theme
    property string icon: "󰅚"
    property string title: "Nothing here"
    property string message: ""

    Layout.fillWidth: true
    Layout.preferredHeight: 92
    spacing: 4

    Text {
        Layout.alignment: Qt.AlignHCenter
        text: root.icon
        color: root.theme.textMuted
        font.family: root.theme.iconFontFamily
        font.pixelSize: root.theme.heroIconSize
        renderType: Text.NativeRendering
    }

    Text {
        Layout.fillWidth: true
        text: root.title
        color: root.theme.text
        horizontalAlignment: Text.AlignHCenter
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        font.weight: Font.DemiBold
        renderType: Text.NativeRendering
    }

    Text {
        visible: root.message !== ""
        Layout.fillWidth: true
        text: root.message
        color: root.theme.textMuted
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.microTextSize
        renderType: Text.NativeRendering
    }
}
