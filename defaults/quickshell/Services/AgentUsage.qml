import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    readonly property string helper: Quickshell.env("HOME") + "/.local/share/blankweave/shell/agent-usage.py"
    property var agents: []
    property string error: ""
    property double now: Date.now() / 1000
    readonly property bool busy: poll.running
    readonly property bool available: agents.some(agent => agent.authenticated)
    readonly property bool low: agents.some(agent => !root.stale(agent)
        && (agent.windows || []).some(window => !root.expired(window) && window.remaining <= 20))
    property bool pendingRefresh: false

    visible: false
    implicitWidth: 0
    implicitHeight: 0

    function planLabel(agent) {
        if (!agent.authenticated)
            return agent.status === "error" ? "Unavailable" : "Not signed in"
        const names = { "prolite": "Pro Lite", "pro": "Pro", "plus": "Plus", "max": "Max",
            "max_5x": "Max 5×", "max_20x": "Max 20×",
            "free": "Free", "team": "Team", "business": "Business", "enterprise": "Enterprise" }
        return names[agent.plan] || (agent.plan && agent.plan !== "unknown"
            ? String(agent.plan).replace(/_/g, " ") : "Signed in")
    }

    function stale(agent) {
        return agent.status === "error" || !agent.updatedAt
            || root.now - Number(agent.updatedAt) > 600
            || root.now < Number(agent.updatedAt)
    }

    function expired(window) {
        return window.resetsAt !== null && Number(window.resetsAt) <= root.now
    }

    function age(agent) {
        if (!agent.updatedAt)
            return ""
        const minutes = Math.max(0, Math.floor((root.now - Number(agent.updatedAt)) / 60))
        return (root.stale(agent) ? "Last reported " : "Updated ")
            + (minutes < 1 ? "just now" : (minutes < 60 ? minutes + "m ago" : Math.floor(minutes / 60) + "h ago"))
    }

    function resetText(window) {
        if (window.resetsAt === null)
            return "Reset time unavailable"
        const minutes = Math.ceil((Number(window.resetsAt) - root.now) / 60)
        if (minutes <= 0)
            return "Reset time passed · awaiting an update"
        if (minutes < 60)
            return "Resets in " + minutes + "m"
        if (minutes < 1440)
            return "Resets in " + Math.floor(minutes / 60) + "h " + minutes % 60 + "m"
        return "Resets in " + Math.floor(minutes / 1440) + "d " + Math.floor(minutes % 1440 / 60) + "h"
    }

    function refresh(force) {
        root.now = Date.now() / 1000
        if (root.busy) {
            root.pendingRefresh = root.pendingRefresh || Boolean(force)
            return
        }
        poll.command = ["python3", root.helper].concat(force ? ["--refresh"] : [])
        poll.running = true
    }

    Process {
        id: poll
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    if (!Array.isArray(data.agents))
                        throw new Error("invalid payload")
                    root.agents = data.agents
                    root.error = ""
                } catch (error) {
                    root.error = "Could not refresh agent usage."
                }
            }
        }
        onExited: {
            if (root.pendingRefresh) {
                root.pendingRefresh = false
                Qt.callLater(() => root.refresh(true))
            }
        }
    }

    // One collector for all screens; the helper caches provider reads for 5m.
    Timer { interval: 30000; running: true; repeat: true; onTriggered: root.refresh(false) }
    Timer { interval: 15000; running: true; repeat: true; onTriggered: root.now = Date.now() / 1000 }
    Component.onCompleted: refresh(false)
}
