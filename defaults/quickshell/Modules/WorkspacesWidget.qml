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

            Rectangle {
                id: workspaceButton

                required property int modelData
                readonly property var workspace: root.workspaceById(modelData)
                readonly property bool occupied: workspace && workspace.toplevels && workspace.toplevels.values.length > 0
                readonly property bool activeWorkspace: workspace
                    && workspace.active
                    && workspace.monitor
                    && workspace.monitor.name === root.bar.screen.name

                Layout.preferredWidth: activeWorkspace ? 28 : 22
                Layout.preferredHeight: theme.widgetHeight
                radius: theme.widgetRadius
                color: activeWorkspace
                    ? theme.accent
                    : (workspaceMouse.containsMouse ? theme.surfaceHover : "transparent")

                Behavior on Layout.preferredWidth {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                Behavior on color {
                    ColorAnimation { duration: 120 }
                }

                Text {
                    anchors.centerIn: parent
                    text: modelData === 10 ? "0" : String(modelData)
                    color: workspaceButton.activeWorkspace
                        ? "white"
                        : (workspaceButton.occupied ? theme.text : theme.textMuted)
                    opacity: workspaceButton.occupied || workspaceButton.activeWorkspace ? 1 : 0.55
                    font.family: theme.monoFontFamily
                    font.pixelSize: 11
                    font.weight: Font.Bold
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
