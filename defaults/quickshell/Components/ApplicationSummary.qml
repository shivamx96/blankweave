import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root

    required property var theme
    property var metrics: []

    Layout.fillWidth: true
    spacing: 0

    Repeater {
        model: root.metrics

        delegate: RowLayout {
            id: metric

            required property int index
            required property var modelData

            Layout.fillWidth: true
            spacing: 0

            Rectangle {
                visible: metric.index > 0
                Layout.preferredWidth: 1
                Layout.preferredHeight: 30
                Layout.rightMargin: 12
                color: root.theme.divider
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: String(metric.modelData.value ?? "—")
                    color: metric.modelData.attention
                        ? root.theme.critical
                        : (metric.modelData.active ? root.theme.accentBright : root.theme.text)
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.textSize + 2
                    font.weight: Font.Bold
                    renderType: Text.NativeRendering
                }

                Text {
                    Layout.fillWidth: true
                    text: String(metric.modelData.label || "")
                    color: root.theme.textMuted
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.microTextSize
                    renderType: Text.NativeRendering
                }
            }
        }
    }
}
