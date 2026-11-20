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
    spacing: root.theme.spacing("xxs")

    function move(index, delta) {
        const next = (index + delta + tabs.length) % tabs.length
        const item = tabRepeater.itemAt(next)
        if (item) item.focusTab()
        selected(tabs[next].id)
    }
    Repeater {
        id: tabRepeater
        model: root.tabs

        delegate: Item {
            id: tab

            required property int index
            required property var modelData
            function focusTab() {
                if (tabMouse.panel) { tabMouse.panel.keyboardMode = true; tabMouse.panel.focusIdentity = tabMouse.focusIdentity }
                tabMouse.forceActiveFocus(Qt.TabFocusReason)
            }
            readonly property string tabId: String(modelData.id || "")
            readonly property bool current: tabId === root.currentId
            readonly property int badge: Number(modelData.badge || 0)

            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(30, tabContent.implicitHeight + root.theme.spacing("xs") * 2)

            Rectangle {
                anchors.fill: parent
                color: tab.current
                    ? root.theme.accentSurface
                    : (tabMouse.containsMouse ? root.theme.surfaceHover : "transparent")
            }

            RowLayout {
                id: tabContent
                anchors.centerIn: parent
                spacing: root.theme.spacing("sm")

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
                    radius: height / 2
                    color: tab.current ? root.theme.accentBright : root.theme.textMuted

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
                    NumberAnimation { duration: root.theme.motionDuration; easing.type: root.theme.motionEasing }
                }
            }

            ControlMouseArea {
                theme: root.theme
                accessibleName: String(tab.modelData.label)
                accessibleRole: Accessible.PageTab
                checkable: true
                checked: tab.current
                focusIdentity: "tab:" + tab.tabId
                Keys.onLeftPressed: root.move(tab.index, -1)
                Keys.onRightPressed: root.move(tab.index, 1)
                id: tabMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selected(tab.tabId)
            }
        }
    }
}
