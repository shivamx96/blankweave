import QtQuick
import QtQuick.Layouts

Rectangle {
    required property var theme

    Layout.preferredWidth: 1
    Layout.preferredHeight: 18
    Layout.leftMargin: 5
    Layout.rightMargin: 5
    radius: 1
    color: theme.divider
}
