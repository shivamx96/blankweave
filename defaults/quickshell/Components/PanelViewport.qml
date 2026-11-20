import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Flickable {
    id: root
    required property var theme
    default property alias content: column.children
    readonly property real naturalHeight: column.implicitHeight
    readonly property bool overflowing: contentHeight > height
    contentWidth: width
    contentHeight: column.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    ColumnLayout {
        id: column
        width: root.width
        spacing: root.theme.spacing("lg")
    }
    ScrollBar.vertical: ScrollBar {
        policy: root.overflowing ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
        width: 4
        contentItem: Rectangle {
            implicitWidth: 4
            implicitHeight: 24
            color: root.theme.textMuted
            radius: 2
        }
        background: Rectangle { color: "transparent" }
    }
}
