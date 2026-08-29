import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root

    required property var theme
    property string icon: ""
    property string iconMark: ""
    property string title: ""
    property string subtitle: ""
    property var actions: []

    signal actionPressed(string actionId)

    Layout.fillWidth: true
    spacing: 10

    VectorMark {
        mark: root.iconMark
        markColor: root.theme.accentBright
        visualSize: root.theme.heroIconSize + 1
    }

    Text {
        visible: root.iconMark === "" && root.icon !== ""
        text: root.icon
        color: root.theme.accentBright
        font.family: root.theme.iconFontFamily
        font.pixelSize: root.theme.heroIconSize
        renderType: Text.NativeRendering
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Text {
            Layout.fillWidth: true
            text: root.title
            color: root.theme.text
            elide: Text.ElideRight
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.textSize
            font.weight: Font.Bold
            font.letterSpacing: 1.2
            renderType: Text.NativeRendering
        }

        Text {
            visible: root.subtitle !== ""
            Layout.fillWidth: true
            text: root.subtitle
            color: root.theme.textMuted
            elide: Text.ElideRight
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.smallTextSize
            renderType: Text.NativeRendering
        }
    }

    RowLayout {
        visible: root.actions.length > 0
        spacing: 2
        Layout.preferredHeight: 28

        Repeater {
            model: root.actions

            delegate: Item {
                id: actionItem

                required property var modelData

                Layout.preferredWidth: 28
                Layout.preferredHeight: 28

                Text {
                    anchors.centerIn: parent
                    text: String(actionItem.modelData.icon || "")
                    color: actionItem.modelData.attention
                        ? root.theme.critical
                        : (actionItem.modelData.active ? root.theme.accentBright : root.theme.text)
                    font.family: root.theme.iconFontFamily
                    font.pixelSize: root.theme.controlIconSize
                    renderType: Text.NativeRendering
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    width: actionItem.modelData.active || actionMouse.containsMouse ? 18 : 0
                    height: 1
                    color: actionItem.modelData.attention ? root.theme.critical : root.theme.accentBright

                    Behavior on width {
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }
                }

                MouseArea {
                    id: actionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.actionPressed(String(actionItem.modelData.id || ""))
                }
            }
        }
    }
}
