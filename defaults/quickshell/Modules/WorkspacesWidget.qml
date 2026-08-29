import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

Item {
    id: root

    required property var bar
    required property var theme

    // Workspaces follow focus between monitors, so each bar lists the ones
    // living on its own monitor: the 1-5 placeholders plus whatever else is
    // here, minus anything currently shown on another monitor (its bar has
    // it). Super+N or a click pulls a workspace over from elsewhere, and
    // clicking the one already showing here sends it on to the next monitor.
    readonly property var workspaceIds: {
        const ids = [1, 2, 3, 4, 5]
        const screenName = String((root.bar.screen && root.bar.screen.name) || "")
        const values = Hyprland.workspaces ? Hyprland.workspaces.values : []
        for (let index = 0; index < values.length; index++) {
            const workspace = values[index]
            const workspaceId = workspace.id
            if (workspaceId < 1 || workspaceId > 10)
                continue
            const monitorName = workspace.monitor ? String(workspace.monitor.name || "") : ""
            const elsewhere = monitorName !== "" && monitorName !== screenName
            const position = ids.indexOf(workspaceId)
            if (elsewhere && position !== -1)
                ids.splice(position, 1)
            else if (!elsewhere && position === -1)
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

    readonly property int monitorCount: Hyprland.monitors ? Hyprland.monitors.values.length : 0

    function activateWorkspace(workspaceId, showingHere) {
        // Hovering the bar has already focused its monitor, so "current
        // monitor" is the one this bar belongs to. Mirrors summon_workspace
        // in keybindings.lua.
        let request
        if (showingHere && root.monitorCount > 1) {
            request = Hyprland.usingLua
                ? "hl.dsp.workspace.move({ monitor = \"+1\" })"
                : "movecurrentworkspacetomonitor +1"
        }
        else {
            request = Hyprland.usingLua
                ? "hl.dsp.focus({ workspace = " + workspaceId + ", on_current_monitor = true })"
                : "focusworkspaceoncurrentmonitor " + workspaceId
        }
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
                    && root.bar.screen
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
                    font.pixelSize: theme.smallTextSize
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
                    onClicked: root.activateWorkspace(workspaceButton.modelData, workspaceButton.activeWorkspace)
                }
            }
        }
    }
}
