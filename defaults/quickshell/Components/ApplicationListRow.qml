import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property var theme
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property string subtitleKind: "neutral"
    property string status: ""
    property string statusKind: "neutral"
    property int rowHeight: 52
    property bool active: false
    property bool busy: false
    property var actions: []

    signal actionPressed(string actionId)

    implicitHeight: rowHeight
    Layout.fillWidth: true
    Layout.preferredHeight: implicitHeight

    readonly property color statusColor: statusKind === "success"
        ? theme.success
        : (statusKind === "warning"
            ? theme.warning
            : (statusKind === "critical" ? theme.critical : theme.textMuted))
    readonly property color subtitleColor: subtitleKind === "success"
        ? theme.success
        : (subtitleKind === "warning"
            ? theme.warning
            : (subtitleKind === "critical" ? theme.critical : theme.textMuted))

    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        height: root.active ? 24 : 12
        color: root.active ? root.theme.accentBright : root.theme.divider

        Behavior on height { NumberAnimation { duration: 140 } }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        spacing: 10

        Text {
            visible: root.icon !== ""
            Layout.preferredWidth: 20
            horizontalAlignment: Text.AlignHCenter
            text: root.icon
            color: root.active ? root.theme.accentBright : root.theme.textMuted
            font.family: root.theme.iconFontFamily
            font.pixelSize: root.theme.controlIconSize
            renderType: Text.NativeRendering
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            Text {
                Layout.fillWidth: true
                text: root.title
                color: root.theme.text
                elide: Text.ElideRight
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.smallTextSize
                font.weight: root.active ? Font.DemiBold : Font.Normal
                renderType: Text.NativeRendering
            }

            Text {
                visible: root.subtitle !== ""
                Layout.fillWidth: true
                text: root.subtitle
                color: root.subtitleColor
                elide: Text.ElideMiddle
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.microTextSize
                renderType: Text.NativeRendering
            }
        }

        Text {
            visible: root.status !== ""
            text: root.busy ? "Working…" : root.status
            color: root.busy ? root.theme.accentBright : root.statusColor
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.microTextSize
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
        }

        RowLayout {
            visible: root.actions.length > 0
            spacing: 1

            Repeater {
                model: root.actions

                delegate: Item {
                    id: actionItem

                    required property var modelData
                    readonly property bool actionEnabled: modelData.enabled === undefined
                        ? true
                        : Boolean(modelData.enabled)

                    Layout.preferredWidth: String(modelData.label || "") !== ""
                        ? Math.max(48, 24 + String(modelData.label || "").length * 7)
                        : 28
                    Layout.preferredHeight: 28
                    opacity: root.busy || !actionEnabled ? 0.35 : 1

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 3

                        Text {
                            text: String(actionItem.modelData.icon || "")
                            color: actionItem.modelData.attention
                                ? root.theme.critical
                                : (actionItem.modelData.active ? root.theme.success : root.theme.text)
                            font.family: root.theme.iconFontFamily
                            font.pixelSize: root.theme.iconSize
                            renderType: Text.NativeRendering
                        }

                        Text {
                            visible: String(actionItem.modelData.label || "") !== ""
                            text: String(actionItem.modelData.label || "")
                            color: actionItem.modelData.active ? root.theme.success : root.theme.textMuted
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.microTextSize
                            font.weight: Font.DemiBold
                            renderType: Text.NativeRendering
                        }
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
                        enabled: !root.busy && actionItem.actionEnabled
                        hoverEnabled: enabled
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.actionPressed(String(actionItem.modelData.id || ""))
                    }
                }
            }
        }
    }
}
