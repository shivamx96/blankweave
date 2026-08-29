import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../Components"
import "../Services"

WidgetFrame {
    id: root

    readonly property string shellDir: Quickshell.env("HOME") + "/.local/share/blankweave/shell"
    property var status: ({
        "available": false,
        "paused": false,
        "displayedCount": 0,
        "waitingCount": 0,
        "historyCount": 0,
        "error": "",
        "notifications": []
    })

    function updateStatus(payload) {
        if (!payload)
            return
        try {
            root.status = JSON.parse(payload)
        } catch (error) {
            root.status = {
                "available": false,
                "paused": false,
                "displayedCount": 0,
                "waitingCount": 0,
                "historyCount": 0,
                "error": "Could not read notification history",
                "notifications": []
            }
        }
    }

    function runControl(arguments) {
        root.bar.run(["dunstctl"].concat(arguments))
        refreshTimer.restart()
    }

    icon: Boolean(status.paused) ? "󰂛" : "󰂚"
    iconOnly: true
    active: notificationPanel.open
    attention: Number(status.waitingCount || 0) > 0
    tooltip: Boolean(status.paused)
        ? "Do not disturb · " + Number(status.waitingCount || 0) + " waiting\nRight-click to resume notifications"
        : Number(status.historyCount || 0) + " archived notifications\nRight-click: do not disturb"

    onPressed: button => {
        if (button === Qt.LeftButton) {
            root.bar.hideTooltip(root)
            notificationPanel.open = !notificationPanel.open
            if (notificationPanel.open)
                statusPoller.refresh()
        }
        else if (button === Qt.RightButton)
            root.runControl(["set-paused", "toggle"])
    }

    ScriptPoller {
        id: statusPoller
        command: root.shellDir + "/notifications-status.sh"
        interval: notificationPanel.open ? 1500 : 5000
        onUpdated: payload => root.updateStatus(payload)
    }

    Timer {
        id: refreshTimer
        interval: 220
        onTriggered: statusPoller.refresh()
    }

    ControlPopup {
        id: notificationPanel
        bar: root.bar
        theme: root.theme
        anchorItem: root
        panelWidth: 420

        onOpenChanged: {
            if (open)
                statusPoller.refresh()
        }

        ControlPanelHeader {
            theme: root.theme
            icon: Boolean(root.status.paused) ? "󰂛" : "󰂚"
            title: "NOTIFICATIONS"
            subtitle: Boolean(root.status.paused)
                ? "Do not disturb · " + Number(root.status.waitingCount || 0) + " waiting"
                : "Dunst notification archive"
            actions: [
                {
                    "id": "dnd",
                    "icon": Boolean(root.status.paused) ? "󰂛" : "󰂚",
                    "active": Boolean(root.status.paused)
                },
                {
                    "id": "clear",
                    "icon": "󰎟",
                    "attention": Number(root.status.historyCount || 0) > 0
                }
            ]
            onActionPressed: actionId => {
                if (actionId === "dnd")
                    root.runControl(["set-paused", "toggle"])
                else if (actionId === "clear")
                    root.runControl(["history-clear"])
            }
        }

        ControlDivider { theme: root.theme }

        ApplicationSummary {
            theme: root.theme
            metrics: [
                {
                    "label": "ARCHIVED",
                    "value": Number(root.status.historyCount || 0),
                    "active": Number(root.status.historyCount || 0) > 0
                },
                {
                    "label": "VISIBLE",
                    "value": Number(root.status.displayedCount || 0)
                },
                {
                    "label": "WAITING",
                    "value": Number(root.status.waitingCount || 0),
                    "active": Number(root.status.waitingCount || 0) > 0
                }
            ]
        }

        ControlSectionLabel {
            theme: root.theme
            text: "RECENT"
        }

        ListView {
            id: notificationList

            visible: (root.status.notifications || []).length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? Math.min(contentHeight, 390) : 0
            model: root.status.notifications || []
            clip: true
            spacing: 1
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                width: 4

                contentItem: Rectangle {
                    implicitWidth: 2
                    color: root.theme.accentBright
                    opacity: 0.72
                }
            }

            delegate: NotificationListRow {
                id: notificationRow

                required property var modelData
                width: notificationList.width - 10
                theme: root.theme
                notificationId: Number(modelData.id || 0)
                appName: String(modelData.appName || "Application")
                title: String(modelData.title || "Notification")
                body: String(modelData.body || "")
                iconPath: String(modelData.iconPath || "")
                urgency: String(modelData.urgency || "normal")
                onRestorePressed: root.runControl(["history-pop", String(notificationId)])
                onDismissPressed: root.runControl(["history-rm", String(notificationId)])
            }
        }

        ApplicationEmptyState {
            visible: (root.status.notifications || []).length === 0
            theme: root.theme
            icon: Boolean(root.status.paused) ? "󰂛" : "󰂚"
            title: Boolean(root.status.available)
                ? "No archived notifications"
                : "Notification history unavailable"
            message: Boolean(root.status.available)
                ? (Boolean(root.status.paused)
                    ? "New notifications will wait quietly until do not disturb is disabled."
                    : "Notifications will appear here after they leave the screen.")
                : String(root.status.error || "Dunst is not responding.")
        }
    }
}
