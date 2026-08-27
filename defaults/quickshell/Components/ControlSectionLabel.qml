import QtQuick

Text {
    required property var theme

    color: theme.textMuted
    font.family: theme.fontFamily
    font.pixelSize: theme.microTextSize
    font.weight: Font.DemiBold
    font.letterSpacing: 1.1
    renderType: Text.NativeRendering
}
