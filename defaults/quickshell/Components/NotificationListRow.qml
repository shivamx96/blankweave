import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

Item {
    id: root

    required property var theme
    property int notificationId: 0
    property string appName: "Application"
    property string title: "Notification"
    property string body: ""
    property string iconPath: ""
    property string urgency: "normal"

    signal restorePressed
    signal dismissPressed

    implicitHeight: 56
    Layout.fillWidth: true
    Layout.preferredHeight: implicitHeight

    readonly property bool critical: urgency === "critical"
    readonly property color indicatorColor: critical ? theme.critical : theme.accentBright
    readonly property url resolvedIcon: {
        if (!root.iconPath)
            return ""
        if (root.iconPath.startsWith("/"))
            return "file://" + root.iconPath
        return Quickshell.iconPath(root.iconPath, "dialog-information")
    }

    Rectangle {
        anchors.fill: parent
        color: rowMouse.containsMouse ? root.theme.surfaceHover : "transparent"
        opacity: 0.72
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
    }

    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        height: root.critical ? 26 : 14
        color: root.indicatorColor

        Behavior on height { NumberAnimation { duration: 140 } }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 4
        spacing: 8

        Item {
            Layout.preferredWidth: 26
            Layout.preferredHeight: 26

            IconImage {
                visible: root.resolvedIcon.toString() !== ""
                anchors.fill: parent
                source: root.resolvedIcon
                mipmap: true
            }

            Text {
                visible: root.resolvedIcon.toString() === ""
                anchors.centerIn: parent
                text: root.critical ? "󰂚" : "󰂞"
                color: root.indicatorColor
                font.family: root.theme.iconFontFamily
                font.pixelSize: root.theme.heroIconSize
                renderType: Text.NativeRendering
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: root.title
                    color: root.theme.text
                    elide: Text.ElideRight
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.smallTextSize
                    font.weight: Font.DemiBold
                    renderType: Text.NativeRendering
                }

                Text {
                    Layout.maximumWidth: 112
                    text: root.appName.toUpperCase()
                    color: root.critical ? root.theme.critical : root.theme.textMuted
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.microTextSize
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.5
                    renderType: Text.NativeRendering
                }
            }

            Text {
                visible: root.body !== ""
                Layout.fillWidth: true
                text: root.body
                color: root.theme.textMuted
                elide: Text.ElideRight
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.microTextSize
                renderType: Text.NativeRendering
            }
        }

        RowLayout {
            spacing: 0

            Repeater {
                model: [
                    { "id": "restore", "icon": "󰑐", "attention": false },
                    { "id": "dismiss", "icon": "󰅖", "attention": true }
                ]

                delegate: Item {
                    id: actionItem

                    required property var modelData
                    Layout.preferredWidth: 25
                    Layout.preferredHeight: 26

                    Text {
                        anchors.centerIn: parent
                        text: String(actionItem.modelData.icon || "")
                        color: actionItem.modelData.attention
                            ? root.theme.critical
                            : root.theme.text
                        font.family: root.theme.iconFontFamily
                        font.pixelSize: root.theme.controlIconSize
                        renderType: Text.NativeRendering
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: actionMouse.containsMouse ? 18 : 0
                        height: 1
                        color: actionItem.modelData.attention
                            ? root.theme.critical
                            : root.theme.accentBright

                        Behavior on width { NumberAnimation { duration: 120 } }
                    }

                    MouseArea {
                        id: actionMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (actionItem.modelData.id === "restore")
                                root.restorePressed()
                            else
                                root.dismissPressed()
                        }
                    }
                }
            }
        }
    }

}
