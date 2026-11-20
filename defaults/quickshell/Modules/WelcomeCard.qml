pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../Components"
Rectangle {
    id: root
    required property var theme
    signal dismissed()
    implicitWidth: theme.osdWidth + theme.spacing("panel") * 8
    implicitHeight: content.implicitHeight + theme.spacing("panel") * 2
    radius: theme.widgetRadius
    color: theme.panelSurface
    border.width: theme.borderWidth
    border.color: theme.outline
    focus: true
    Keys.onEscapePressed: root.dismissed()
    Keys.onReturnPressed: root.dismissed()
    Keys.onEnterPressed: root.dismissed()
    // No transition, including when reduced motion is selected.
    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: root.theme.spacing("panel")
        spacing: root.theme.spacing("lg")
        Repeater {
            model: ["Welcome to Blankweave", "Super+Space   Launcher", "Super+Return   Terminal",
                    "Super+,   Settings", "Super+/   All shortcuts", "Super+Escape   Power menu",
                    "Find your preferences in Settings and every key in All shortcuts."]
            delegate: Text {
                required property string modelData
                Layout.fillWidth: true
                text: modelData
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.smallTextSize
            }
        }
        ControlAction {
            objectName: "welcomeGotIt"
            theme: root.theme
            label: "Got it"
            onPressed: root.dismissed()
        }
    }
}
