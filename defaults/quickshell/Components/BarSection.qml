import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    required property var theme
    default property alias content: contentRow.children

    implicitWidth: contentRow.implicitWidth + theme.islandPadding * 2
    implicitHeight: theme.barHeight
    radius: theme.islandRadius
    color: theme.surface
    border.width: 1
    border.color: theme.outline

    RowLayout {
        id: contentRow
        anchors.fill: parent
        anchors.margins: theme.islandPadding
        spacing: 2
    }

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.radius
        anchors.rightMargin: root.radius
        height: 1
        color: theme.dark ? "#4067a6ff" : "#55ffffff"
    }
}
