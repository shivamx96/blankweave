import QtQuick

// A solid fallback with an optional static wash. Children remain above the
// material; high-contrast mode disables it through Theme.gradientEnabled.
Rectangle {
    id: root
    required property var surfaceTheme
    property bool decorative: true
    border.width: 0

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: root.decorative && root.surfaceTheme.gradientEnabled === true
        gradient: Gradient {
            orientation: root.surfaceTheme.gradientHorizontal ? Gradient.Horizontal : Gradient.Vertical
            GradientStop { position: 0; color: root.surfaceTheme.gradientStart || "transparent" }
            GradientStop { position: 1; color: root.surfaceTheme.gradientEnd || "transparent" }
        }
        border.width: root.border.width
        border.color: root.border.color
    }
}
