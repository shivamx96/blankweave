import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

Item {
    id: root

    required property var bar
    required property var theme

    readonly property var workspaceIds: {
        const ids = [1, 2, 3, 4, 5]
        const values = Hyprland.workspaces ? Hyprland.workspaces.values : []
        for (let index = 0; index < values.length; index++) {
            const workspaceId = values[index].id
            if (workspaceId > 5 && workspaceId <= 10 && ids.indexOf(workspaceId) === -1)
                ids.push(workspaceId)
        }
        return ids.sort((left, right) => left - right)
    }

    function workspaceById(workspaceId) {
        const values = Hyprland.workspaces ? Hyprland.workspaces.values : []
        for (let index = 0; index < values.length; index++) {
            if (values[index].id === workspaceId)
                return values[index]
        }
        return null
    }

    function activateWorkspace(workspaceId) {
        const request = Hyprland.usingLua
            ? "hl.dsp.focus({ workspace = \"" + workspaceId + "\" })"
            : "workspace " + workspaceId
        Hyprland.dispatch(request)
    }

    implicitWidth: row.implicitWidth
    implicitHeight: theme.widgetHeight
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 2

        Repeater {
            model: root.workspaceIds

            Item {
                id: workspaceButton

                required property int modelData
                readonly property var workspace: root.workspaceById(modelData)
                readonly property bool occupied: workspace && workspace.toplevels && workspace.toplevels.values.length > 0
                readonly property bool activeWorkspace: workspace
                    && workspace.active
                    && workspace.monitor
                    && workspace.monitor.name === root.bar.screen.name

                Layout.preferredWidth: 24
                Layout.preferredHeight: theme.widgetHeight

                Text {
                    anchors.centerIn: parent
                    text: modelData === 10 ? "0" : String(modelData)
                    color: workspaceButton.activeWorkspace
                        ? theme.accentBright
                        : (workspaceButton.occupied ? theme.text : theme.textMuted)
                    opacity: workspaceButton.occupied || workspaceButton.activeWorkspace ? 1 : 0.55
                    font.family: theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.15
                }

                Rectangle {
                    visible: workspaceButton.occupied
                        && !workspaceButton.activeWorkspace
                        && !workspaceMouse.containsMouse
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 3
                    width: 3
                    height: 3
                    radius: 2
                    color: theme.accentBright
                }

                Item {
                    id: workspaceTrace

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 1
                    width: workspaceButton.activeWorkspace ? 17 : (workspaceMouse.containsMouse ? 11 : 0)
                    height: 2

                    Behavior on width {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: workspaceButton.activeWorkspace ? 2 : 1
                        color: workspaceButton.activeWorkspace ? theme.accentBright : theme.outlineStrong
                        opacity: workspaceButton.activeWorkspace ? 0.82 : 0.65
                    }

                }

                MouseArea {
                    id: workspaceMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.bar.showTooltip(workspaceButton, "Workspace " + workspaceButton.modelData)
                    onExited: root.bar.hideTooltip(workspaceButton)
                    onClicked: root.activateWorkspace(workspaceButton.modelData)
                }
            }
        }
    }
}
