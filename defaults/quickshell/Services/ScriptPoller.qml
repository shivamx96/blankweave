import QtQuick
import Quickshell
import Quickshell.Io
import "PollerOutput.js" as PollerOutput

Item {
    id: root
    property string command: ""
    property int interval: 5000
    // Includes slow helpers, but never permits an unbounded run (even at interval 0).
    property int timeout: Math.max(1000, Math.min(30000, interval > 0 ? interval * 0.8 : 10000))
    property bool jsonOutput: true
    property string output: ""
    property bool ready: false
    property bool refreshPending: false
    property string error: ""
    property double lastUpdated: 0
    property double now: Date.now()
    readonly property bool stale: !lastUpdated || error !== ""
        || (interval > 0 && now - lastUpdated > Math.max(1000, interval * 3))
    readonly property string staleText: stale ? "Last updated: "
        + (lastUpdated ? new Date(lastUpdated).toLocaleString() : "never")
        + (error ? " · " + error : "") : ""
    readonly property bool running: process.running
    signal updated(string payload)
    visible: false

    function refresh() {
        if (!command) return
        if (process.running) {
            refreshPending = true
            return
        }
        refreshPending = false
        // Preserve the session PATH, explicitly add user executables, and suppress
        // BASH_ENV startup hooks without sourcing a login profile.
        // GNU timeout creates a process group: TERM then KILL reaches descendants,
        // including ones ignoring TERM. Do not use --foreground here.
        process.command = ["/usr/bin/env",
            "PATH=" + Quickshell.env("HOME") + "/.local/bin:" + Quickshell.env("PATH"),
            "BASH_ENV=", "/usr/bin/timeout", "--kill-after=0.25s",
            Math.max(1, timeout) / 1000 + "s", "/usr/bin/bash", "-c", command]
        process.running = true
    }

    function accept(text, code, status) {
        now = Date.now()
        if (code !== 0 || status !== 0) {
            error = code === 124 || code === 137 || (status !== 0 && code === 9) ? "Collection timed out" : "Collection failed (" + code + ")"
            return
        }
        let payload = String(text || "").trim()
        if (jsonOutput) {
            try {
                const decoded = PollerOutput.decode(payload)
                payload = decoded.payload
                const parsed = decoded.data
                if (parsed.stale === true) {
                    error = String(parsed.error || "Source reports stale data")
                    output = payload
                    ready = true
                    updated(payload)
                    return
                }
            } catch (e) {
                error = "Invalid JSON output"
                return
            }
        }
        output = payload
        ready = true
        lastUpdated = now
        error = ""
        updated(payload)
    }

    Process {
        id: process
        stdout: StdioCollector { id: collector; waitForEnd: true }
        // stderr is deliberately not collected into stdout.
        onExited: (code, status) => {
            root.accept(collector.text, code, status)
            if (root.refreshPending) Qt.callLater(root.refresh)
        }
    }
    Timer {
        interval: Math.max(250, root.interval)
        running: root.interval > 0 && root.command !== ""
        repeat: true
        onTriggered: root.refresh()
    }
    Timer { interval: 500; running: true; repeat: true; onTriggered: root.now = Date.now() }
    Component.onCompleted: { if (command) Qt.callLater(refresh) }
}
