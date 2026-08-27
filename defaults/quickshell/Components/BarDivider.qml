import QtQuick
import QtQuick.Layouts

Rectangle {
    required property var theme

    Layout.preferredWidth: 1
    Layout.preferredHeight: 22
    Layout.leftMargin: theme.dividerMargin
    Layout.rightMargin: theme.dividerMargin
    color: "transparent"

    gradient: Gradient {
        orientation: Gradient.Vertical
        GradientStop { position: 0; color: "transparent" }
        GradientStop { position: 0.22; color: theme.divider }
        GradientStop { position: 0.78; color: theme.divider }
        GradientStop { position: 1; color: "transparent" }
    }
}
