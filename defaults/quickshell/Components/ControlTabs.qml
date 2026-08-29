import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root

    required property var theme
    // [{ "id": "repos", "label": "REPOS", "badge": 3 }]
    property var tabs: []
    property string currentId: ""

    signal selected(string tabId)

    Layout.fillWidth: true
    spacing: 2

    Repeater {
        model: root.tabs

        delegate: Item {
            id: tab

            required property var modelData
            readonly property string tabId: String(modelData.id || "")
            readonly property bool current: tabId === root.currentId
            readonly property int badge: Number(modelData.badge || 0)

            Layout.fillWidth: true
            Layout.preferredHeight: 30

            Rectangle {
                anchors.fill: parent
                color: tab.current
                    ? root.theme.accentSurface
                    : (tabMouse.containsMouse ? root.theme.surfaceHover : "transparent")
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: 6

                Text {
                    text: String(tab.modelData.label || "")
                    color: tab.current ? root.theme.accentBright : root.theme.textMuted
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.microTextSize
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.1
                    renderType: Text.NativeRendering
                }

                Rectangle {
                    visible: tab.badge > 0
                    Layout.preferredWidth: Math.max(16, badgeLabel.implicitWidth + 8)
                    Layout.preferredHeight: 16
                    radius: 8
                    color: tab.current ? root.theme.accentBright : root.theme.divider

                    Text {
                        id: badgeLabel
                        anchors.centerIn: parent
                        text: tab.badge
                        color: root.theme.canvas
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.microTextSize - 1
                        font.weight: Font.Bold
                        renderType: Text.NativeRendering
                    }
                }
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                width: tab.current ? parent.width : (tabMouse.containsMouse ? 18 : 0)
                height: 1
                color: root.theme.accentBright

                Behavior on width {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
            }

            MouseArea {
                id: tabMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selected(tab.tabId)
            }
        }
    }
}
