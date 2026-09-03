import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")) + "/blankweave/install.conf"
    readonly property string statusCommand: "voxtype status --follow --format json --extended --icon-theme text"
    property bool featureEnabled: false
    property bool daemonRunning: false
    property bool statusSeen: false
    property bool watcherWanted: true
    property string daemonState: "stopped"
    property string model: "—"
    property string device: "—"
    property string backend: "—"
    property string error: ""
    readonly property bool available: featureEnabled && daemonRunning && statusSeen
    readonly property bool busy: daemonState === "recording" || daemonState === "transcribing"

    visible: false
    implicitWidth: 0
    implicitHeight: 0

    function loadFeatures(text) {
        let selected = []
        const lines = String(text || "").split(/\r?\n/)
        for (let index = 0; index < lines.length; index++) {
            const line = lines[index].replace(/#.*/, "").trim()
            const match = /^profiles\s*=\s*(.*)$/.exec(line)
            if (match) {
                selected = match[1].trim().split(/\s+/).filter(value => value !== "")
                break
            }
        }
        root.featureEnabled = selected.indexOf("voice-dictation") >= 0
        if (root.featureEnabled)
            healthPoller.refresh()
        else
            root.resetStatus()
    }

    function resetStatus() {
        root.daemonRunning = false
        root.statusSeen = false
        root.daemonState = "stopped"
        root.error = ""
    }

    function updateStatus(payload) {
        if (!payload)
            return
        try {
            const next = JSON.parse(payload)
            const nextState = String(next.alt || "stopped")
            root.daemonState = ["idle", "recording", "transcribing"].indexOf(nextState) >= 0
                ? nextState
                : "stopped"
            root.model = String(next.model || "—")
            root.device = String(next.device || "—")
            root.backend = String(next.backend || "—")
            root.error = ""
            root.statusSeen = true
        } catch (error) {
            root.error = "Could not read VoxType status"
            root.statusSeen = false
        }
    }

    FileView {
        path: root.configPath
        watchChanges: true
        printErrors: false
        onLoaded: root.loadFeatures(text())
        onLoadFailed: {
            root.featureEnabled = false
            root.resetStatus()
        }
        onFileChanged: reload()
    }

    ScriptPoller {
        id: healthPoller
        command: root.featureEnabled
            ? "systemctl --user is-active --quiet voxtype.service && printf active || printf inactive"
            : ""
        interval: root.featureEnabled ? 4000 : 0
        onUpdated: payload => {
            const running = String(payload || "").trim() === "active"
            root.daemonRunning = running
            if (running) {
                root.watcherWanted = true
            } else {
                root.statusSeen = false
                root.daemonState = "stopped"
            }
        }
    }

    Process {
        id: statusWatcher
        command: ["bash", "-lc", "exec " + root.statusCommand]
        running: root.featureEnabled && root.daemonRunning && root.watcherWanted

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root.updateStatus(data)
        }

        onExited: {
            root.watcherWanted = false
            root.statusSeen = false
            if (root.featureEnabled && root.daemonRunning)
                retryTimer.restart()
        }
    }

    Timer {
        id: retryTimer
        interval: 1500
        onTriggered: root.watcherWanted = true
    }
}
