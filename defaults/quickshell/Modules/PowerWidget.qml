import QtQuick
import QtQuick.Layouts
import "../Components"

WidgetFrame {
    id: root

    property string pendingAction: ""

    function execute(command) {
        confirmTimer.stop()
        pendingAction = ""
        powerPanel.open = false
        Qt.callLater(() => root.bar.run(command))
    }

    function requestGuarded(action, command) {
        if (pendingAction === action) {
            root.execute(command)
            return
        }
        pendingAction = action
        confirmTimer.restart()
    }

    function confirmationLabel(action, label) {
        return pendingAction === action ? "Confirm" : label
    }

    icon: "󰐥"
    iconPixelSize: theme.barIconSize + 3
    iconOnly: true
    tooltip: "Session and power"
    horizontalPadding: 6
    active: powerPanel.open

    onPressed: button => {
        if (button === Qt.LeftButton) {
            root.bar.hideTooltip(root)
            powerPanel.open = !powerPanel.open
        }
    }

    Timer {
        id: confirmTimer
        interval: 3500
        onTriggered: root.pendingAction = ""
    }

    ControlPopup {
        id: powerPanel
        bar: root.bar
        theme: root.theme
        anchorItem: root
        panelWidth: 340

        onOpenChanged: {
            if (!open) {
                confirmTimer.stop()
                root.pendingAction = ""
            }
        }

        ControlPanelHeader {
            theme: root.theme
            icon: "󰐥"
            title: "SESSION"
            subtitle: root.pendingAction
                ? "Select again to confirm"
                : "Lock, suspend, or end this session"
        }

        ControlDivider { theme: root.theme }

        ControlSectionLabel {
            theme: root.theme
            text: "SESSION"
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ControlAction {
                theme: root.theme
                icon: "󰌾"
                label: "Lock"
                onPressed: root.execute(["hyprlock"])
            }

            ControlAction {
                theme: root.theme
                icon: "󰍃"
                label: root.confirmationLabel("logout", "Log out")
                attention: root.pendingAction === "logout"
                onPressed: root.requestGuarded("logout", ["uwsm", "stop"])
            }
        }

        ControlSectionLabel {
            theme: root.theme
            text: "POWER"
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            ControlAction {
                theme: root.theme
                icon: "󰒲"
                label: "Suspend"
                onPressed: root.execute(["systemctl", "suspend"])
            }

            ControlAction {
                theme: root.theme
                icon: "󰜉"
                label: root.confirmationLabel("reboot", "Restart")
                attention: root.pendingAction === "reboot"
                onPressed: root.requestGuarded("reboot", ["systemctl", "reboot"])
            }

            ControlAction {
                theme: root.theme
                icon: "󰐥"
                label: root.confirmationLabel("shutdown", "Shut down")
                attention: root.pendingAction === "shutdown"
                onPressed: root.requestGuarded("shutdown", ["systemctl", "poweroff"])
            }
        }

        Text {
            visible: root.pendingAction !== ""
            Layout.fillWidth: true
            text: "This action will close the current session."
            color: root.theme.critical
            horizontalAlignment: Text.AlignHCenter
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.microTextSize
            renderType: Text.NativeRendering
        }
    }
}
