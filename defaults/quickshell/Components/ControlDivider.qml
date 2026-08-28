import QtQuick
import QtQuick.Layouts

Rectangle {
    required property var theme

    Layout.fillWidth: true
    Layout.preferredHeight: 1
    color: theme.divider
}
