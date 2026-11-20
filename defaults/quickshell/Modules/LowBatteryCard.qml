import QtQuick
import QtQuick.Layouts
import "../Components"

Rectangle {
    id: root
    required property var theme
    required property var power
    readonly property var warning: power.lowBattery
    readonly property color warningColor: warning.warningLevel === 5 ? theme.critical : theme.warning
    implicitWidth: content.implicitWidth + theme.spacing("panel") * 2
    implicitHeight: content.implicitHeight + theme.spacing("panel") * 2
    radius: root.theme.widgetRadius
    color: root.theme.panelSurface
    border.width: root.theme.borderWidth
    border.color: root.warningColor

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.warning.dismiss()
    }
    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: root.theme.spacing("xl")
        Text {
            text: "󰂎"
            color: root.warningColor
            font.family: root.theme.iconFontFamily
            font.pixelSize: root.theme.heroIconSize
        }
        ColumnLayout {
            spacing: root.theme.spacing("xs")
            Text {
                // The live level, not the threshold crossed: a resume at 3% says 3%.
                text: "Battery low — " + (Number.isFinite(root.warning.percentage)
                    ? Math.round(root.warning.percentage) : root.warning.warningLevel) + "%"
                textFormat: Text.PlainText
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.textSize
                font.weight: Font.DemiBold
            }
            Text {
                text: root.warning.warningLevel === 5
                    ? "Plug in now or suspend to keep your work"
                    : "Plug in soon to keep your work safe"
                textFormat: Text.PlainText
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.smallTextSize
            }
            ControlAction {
                objectName: "lowBatterySuspend"
                visible: root.warning.warningLevel === 5
                theme: root.theme
                icon: "󰒲"
                label: "Suspend"
                attention: true
                onPressed: { root.warning.dismiss(); root.power.suspend() }
            }
        }
    }
}
