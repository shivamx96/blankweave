import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property var theme
    default property alias content: contentRow.children

    implicitWidth: contentRow.implicitWidth
    implicitHeight: theme.barHeight

    RowLayout {
        id: contentRow
        anchors.fill: parent
        spacing: 2
    }
}
