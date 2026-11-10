pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as Controls

Controls.Menu {
    id: root
    required property var theme
    property var entries: []
    signal chosen(var entry)
    width: 280
    padding: root.theme.spacing("xs")
    topMargin: root.theme.spacing("md")
    bottomMargin: root.theme.spacing("md")
    popupType: Controls.Popup.Item
    background: Rectangle {
        color: root.theme.panelSurface
        radius: root.theme.widgetRadius
        border.width: root.theme.borderWidth
        border.color: root.theme.outline
    }
    contentItem: ListView {
        implicitHeight: Math.min(contentHeight, 320)
        model: root.contentModel
        currentIndex: root.currentIndex
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Controls.ScrollBar.vertical: SettingsScrollBar { theme: root.theme }
    }
    Repeater {
        model: root.entries
        delegate: Controls.MenuItem {
            id: entry
            required property var modelData
            objectName: "operationMenu_" + modelData.action.key
            text: modelData.label
            implicitHeight: title.implicitHeight + 20
            leftPadding: root.theme.spacing("xl")
            rightPadding: root.theme.spacing("xl")
            hoverEnabled: true
            Accessible.name: text
            contentItem: Text {
                id: title
                text: entry.text
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.smallTextSize
                color: entry.highlighted ? root.theme.accentBright : root.theme.text
            }
            background: Rectangle {
                color: entry.down ? root.theme.surfacePressed : entry.highlighted ? root.theme.accentSurface : "transparent"
                radius: root.theme.widgetRadius
                border.width: entry.visualFocus ? Math.max(1, root.theme.borderWidth) : 0
                border.color: root.theme.accentBright
            }
            onTriggered: root.chosen(modelData)
        }
    }
}
