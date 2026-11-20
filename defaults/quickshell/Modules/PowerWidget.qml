import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../Components"
import "../Services"
import "../Services/PowerActions.js" as PowerActions

WidgetFrame {
    id: root

    property bool restartRequired: false
    FileView {
        id: restartMarker
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/blankweave/restart-required"
        watchChanges: true
        printErrors: false
        onLoaded: root.restartRequired = true
        onLoadFailed: root.restartRequired = false
        onFileChanged: reload()
    }

    property string pendingAction: ""
    // tty1 signs the user straight back in unless the saved policy says "no",
    // so stopping the session there restarts it rather than logging out.
    property string signInPolicyPath: "/etc/blankweave/signin.conf"
    property bool automaticSignIn: true
    readonly property string sessionExitLabel: PowerActions.exitLabel(automaticSignIn)
    FileView {
        path: root.signInPolicyPath
        watchChanges: true
        printErrors: false
        onLoaded: root.automaticSignIn = text().trim() !== "no"
        onLoadFailed: root.automaticSignIn = true
        onFileChanged: reload()
    }
    function handleKey(event) { powerPanel.handleKey(event) }
    SettingsTask {
        id: hibernation
        script: "operations-settings.py"
        arguments: ["hibernate"]
        active: powerPanel.open
    }

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
        panelId: "power"
        id: powerPanel
        bar: root.bar
        theme: root.theme
        anchorItem: root
        panelWidth: 340

        onOpenChanged: {
            if (open) restartMarker.reload()
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

        Text {
            visible: root.restartRequired
            text: "Restart to finish updating"
            color: root.theme.warning
            font.pixelSize: root.theme.smallTextSize
            font.family: root.theme.fontFamily
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
                id: lockAction
                theme: root.theme
                icon: "󰌾"
                label: "Lock"
                onPressed: root.execute(PowerActions.lockCommand())
            }

            ControlAction {
                id: logoutAction
                theme: root.theme
                icon: "󰍃"
                label: root.confirmationLabel("logout", root.sessionExitLabel)
                attention: root.pendingAction === "logout"
                onPressed: root.requestGuarded("logout", PowerActions.exitCommand())
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
                id: suspendAction
                theme: root.theme
                icon: "󰒲"
                label: "Suspend"
                onPressed: root.execute(PowerActions.suspendCommand())
            }

            ControlAction {
                id: rebootAction
                theme: root.theme
                icon: "󰜉"
                label: root.confirmationLabel("reboot", "Restart")
                attention: root.pendingAction === "reboot"
                onPressed: root.requestGuarded("reboot", PowerActions.restartCommand())
            }

            ControlAction {
                id: shutdownAction
                theme: root.theme
                icon: "󰐥"
                label: root.confirmationLabel("shutdown", "Shut down")
                attention: root.pendingAction === "shutdown"
                onPressed: root.requestGuarded("shutdown", PowerActions.shutdownCommand())
            }
        }

        ControlAction {
            id: hibernateAction
            theme: root.theme
            icon: "󰒲"
            label: root.confirmationLabel("hibernate", "Hibernate")
            visible: hibernation.ready && (hibernation.data.actions || []).some(action => action.key === "hibernate")
            enabled: hibernation.writable
            attention: root.pendingAction === "hibernate"
            onPressed: {
                if (root.pendingAction === "hibernate") {
                    hibernation.apply({action: "hibernate", confirmed: true})
                    root.pendingAction = ""
                    confirmTimer.stop()
                } else {
                    root.pendingAction = "hibernate"
                    confirmTimer.restart()
                }
            }
        }
        Text {
            visible: text !== ""
            text: hibernation.error || (hibernation.ready && hibernation.data.job && hibernation.data.job.phase === "failed" ? hibernation.data.job.message : ""); textFormat: Text.PlainText
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            color: root.theme.warning; font.pixelSize: root.theme.smallTextSize
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
