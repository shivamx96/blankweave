import QtQuick
import QtQuick.Layouts
Rectangle {
    id: root
    required property var theme
    required property var feedback
    implicitWidth: theme.osdWidth
    implicitHeight: content.implicitHeight + theme.spacing("panel") * 2
    radius: theme.widgetRadius
    color: theme.panelSurface
    border.width: theme.borderWidth
    border.color: theme.outlineStrong
    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: root.theme.spacing("panel") }
        spacing: root.theme.spacing("md")
        RowLayout {
            spacing: root.theme.spacing("xl")
            Text { text: root.feedback.icon; color: root.theme.accentBright; font.family: root.theme.iconFontFamily; font.pixelSize: root.theme.controlIconSize }
            Text { text: root.feedback.label; color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.textSize }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: root.theme.osdBarHeight
            radius: height / 2
            color: root.theme.surfaceRaised
            Rectangle {
                width: parent.width * root.feedback.level; height: parent.height; radius: parent.radius
                color: root.theme.accentBright
                Behavior on width { NumberAnimation { duration: root.theme.reducedMotion ? 0 : root.theme.motionDuration } }
            }
        }
    }
}
