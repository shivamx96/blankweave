pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../Settings"

RowLayout {
    id: root

    required property var theme
    property string icon: ""
    property string iconMark: ""
    property string title: ""
    property string subtitle: ""
    // Each action requires id and a non-empty human label. kind defaults to button.
    // Switches additionally use checked; pending prevents repeated activation.
    property var actions: []
    property bool atBottom: false

    signal actionPressed(string actionId)

    Layout.fillWidth: true
    spacing: root.theme.spacing("lg")

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
        spacing: root.theme.spacing("xxs")

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
        spacing: root.theme.spacing("xxs")
        Layout.preferredHeight: 28

        Repeater {
            model: root.actions

            delegate: Item {
                id: actionItem

                required property var modelData

                readonly property bool isSwitch: modelData.kind === "switch"
                readonly property bool pending: Boolean(modelData.pending)
                readonly property string actionLabel: String(modelData.label || "")
                readonly property bool available: modelData.enabled !== false && !pending
                Layout.preferredWidth: isSwitch ? 44 : 28
                Layout.preferredHeight: 36
                activeFocusOnTab: false
                Accessible.role: Accessible.Button
                Accessible.name: actionLabel
                Accessible.onPressAction: activate()
                function activate() {
                    if (available)
                        root.actionPressed(String(modelData.id))
                }

                Text {
                    visible: !actionItem.isSwitch
                    anchors.centerIn: parent
                    text: String(actionItem.modelData.icon || "")
                    opacity: actionItem.available ? 1 : 0.45
                    color: actionItem.modelData.attention
                        ? root.theme.critical
                        : (actionItem.modelData.active ? root.theme.accentBright : root.theme.text)
                    font.family: root.theme.iconFontFamily
                    font.pixelSize: root.theme.controlIconSize
                    renderType: Text.NativeRendering
                }
                Rectangle {
                    visible: !actionItem.isSwitch
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    width: actionItem.activeFocus || actionMouse.containsMouse || actionItem.modelData.active ? 18 : 0
                    height: 1
                    color: root.theme.accentBright
                }
                SettingsSwitch {
                    id: toggle
                    objectName: "headerSwitch"
                    visible: actionItem.isSwitch
                    anchors.fill: parent
                    theme: root.theme
                    enabled: actionItem.available
                    checked: Boolean(actionItem.modelData.checked)
                    Accessible.name: actionItem.actionLabel
                    // The backend owns checked; never leave an optimistic local toggle.
                    onToggled: checked = Qt.binding(() => Boolean(actionItem.modelData.checked))
                    onClicked: actionItem.activate()
                }
                Text {
                    visible: actionItem.pending
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    text: "…"
                    color: root.theme.textMuted
                    font.pixelSize: root.theme.microTextSize
                }
                ControlMouseArea {
                    theme: root.theme
                    accessibleName: actionItem.actionLabel
                    id: actionMouse
                    anchors.fill: parent
                    acceptedButtons: actionItem.isSwitch ? Qt.NoButton : Qt.LeftButton
                    hoverEnabled: true
                    cursorShape: actionItem.available ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: actionItem.activate()
                }
                PopupWindow {
                    id: hint
                    visible: actionItem.actionLabel !== "" && (actionMouse.containsMouse || toggle.hovered || actionItem.activeFocus || actionMouse.activeFocus || toggle.activeFocus)
                    color: "transparent"
                    implicitWidth: Math.min(360, hintText.implicitWidth + 24)
                    implicitHeight: hintText.implicitHeight + 18
                    anchor {
                        id: hintAnchor
                        window: actionItem.QsWindow.window
                        adjustment: PopupAdjustment.Slide
                        edges: root.atBottom ? Edges.Top | Edges.Left : Edges.Bottom | Edges.Left
                        gravity: root.atBottom ? Edges.Top | Edges.Right : Edges.Bottom | Edges.Right
                        onAnchoring: {
                            const win = actionItem.QsWindow.window
                            if (!win) return
                            const point = actionItem.mapToItem(win.contentItem, actionItem.width / 2 - hint.width / 2,
                                root.atBottom ? -7 : actionItem.height + 7)
                            hintAnchor.rect.x = Math.round(point.x)
                            hintAnchor.rect.y = Math.round(point.y)
                        }
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: root.theme.widgetRadius
                        color: root.theme.surfaceRaised
                        border.width: 1
                        border.color: root.theme.outlineStrong
                        Text {
                            id: hintText
                            anchors.centerIn: parent
                            width: Math.min(336, implicitWidth)
                            text: actionItem.actionLabel + (actionItem.pending ? " · Applying…" : "")
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            color: root.theme.text
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.smallTextSize
                        }
                    }
                }
            }
        }
    }
}
