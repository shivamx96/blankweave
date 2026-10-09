import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    required property var theme
    required property var preferences
    property string helper: Quickshell.env("HOME") + "/.local/share/blankweave/shell/theme-apply.sh"
    property var themes: []
    property bool loaded: false
    property string operationError: ""
    readonly property string error: operationError || preferences.writeError || ""
    property bool systemPending: false
    property bool foldersPending: false
    property bool bootSplashPending: false
    property string systemHelper: "/usr/lib/blankweave/theme-system"
    property bool syncAvailable: false
    property string syncState: "idle"
    property string syncMessage: ""
    property bool syncStarted: false
    property bool statusValid: false
    readonly property bool syncing: systemSync.running
        || ["authenticating", "applying", "verifying"].includes(syncState)
    property var syncCommand: [
        "/usr/bin/pkexec", "--disable-internal-agent", systemHelper, "--progress",
        Quickshell.env("HOME"), Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    ]
    readonly property string pendingDescription: foldersPending && bootSplashPending
        ? "Folder colors and boot appearance haven’t caught up with your desktop theme."
        : foldersPending ? "Folder colors haven’t caught up with your desktop theme."
        : "Boot appearance hasn’t caught up with your desktop theme."
    readonly property bool ready: loaded && preferences.ready
    readonly property bool busy: listing.running || status.running || action.running || syncing

    function readStatus() {
        statusValid = false
        status.running = true
    }

    function syncSystem() {
        if (!ready || busy || !systemPending || !syncAvailable) return
        operationError = ""
        syncState = "authenticating"
        syncMessage = "Waiting for authentication…"
        syncStarted = false
        systemSync.command = syncCommand
        systemSync.running = true
    }

    function refresh() {
        if (busy) return
        operationError = ""
        listing.running = true
        readStatus()
    }

    function choices(id) {
        if (id === "theme") return themes.map(row => row.name)
        if (id === "mode") return ["Dark", "Light"]
        if (id === "bar-position") return ["Top", "Bottom"]
        if (id === "bar-visibility") return ["Always visible", "Hide in fullscreen", "Auto-hide"]
        return []
    }

    function selection(id) {
        if (id === "theme") return themes.findIndex(row => row.id === theme.themeId)
        if (id === "mode") return theme.mode === "light" ? 1 : 0
        if (id === "bar-position") return preferences.bar.position === "bottom" ? 1 : 0
        if (id === "bar-visibility") return ["always", "fullscreen", "auto-hide"].indexOf(preferences.bar.visibilityMode)
        return -1
    }

    function apply(id, index) {
        if (!ready || busy || index < 0 || index >= choices(id).length) return
        operationError = ""
        syncState = "idle"
        syncMessage = ""
        if (id === "bar-position") preferences.bar.position = ["top", "bottom"][index]
        else if (id === "bar-visibility") preferences.bar.visibilityMode = ["always", "fullscreen", "auto-hide"][index]
        else if (id === "theme" || id === "mode") {
            action.command = id === "theme" ? ["bash", helper, "set", themes[index].id]
                : ["bash", helper, "mode", ["dark", "light"][index]]
            action.running = true
        }
    }

    property Process listing: Process {
        command: ["bash", root.helper, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const entries = JSON.parse(text)
                    if (!Array.isArray(entries)) throw new Error("Invalid theme list")
                    root.themes = entries.filter(row => !row.invalid && row.id)
                        .map(row => ({ id: String(row.id), name: String(row.name || row.id) }))
                } catch (error) {
                    root.themes = []
                    root.operationError = "Could not read available themes. Check your installation and retry."
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.loaded = true
            if (exitCode !== 0 || exitStatus !== 0)
                root.operationError = "Theme discovery failed. Check your installation and retry."
        }
    }
    property Process status: Process {
        command: ["bash", root.helper, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const value = JSON.parse(text)
                    if (!value.system || typeof value.system.pending !== "boolean")
                        throw new Error("Invalid system appearance status")
                    root.foldersPending = Boolean(value.system.folders)
                    root.bootSplashPending = Boolean(value.system.bootSplash)
                    root.systemPending = Boolean(value.system && value.system.pending)
                    root.statusValid = true
                } catch (error) {
                    root.operationError = "Could not read theme status. Retry to refresh it."
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 || exitStatus !== 0)
                root.operationError = "Could not read theme status. Retry to refresh it."
            if (root.syncState === "verifying") {
                const verified = exitCode === 0 && exitStatus === 0 && root.statusValid
                root.syncState = verified && !root.systemPending ? "success" : "error"
                root.syncMessage = !verified ? "Couldn’t verify system appearance. Refresh to check it again."
                    : root.systemPending ? "Some changes are still pending. Check the theme’s system components and try again."
                    : "System appearance is up to date."
            }
        }
    }
    property Process action: Process {
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 || exitStatus !== 0)
                root.operationError = "The theme could not be fully applied. Retry or run blankweave theme status for details."
            root.readStatus()
        }
    }

    // This file is installed by the privileged installer. Never elevate a
    // script from the user's repository or managed shell directory here.
    property FileView systemHelperFile: FileView {
        path: root.systemHelper
        watchChanges: true
        printErrors: false
        onLoaded: root.syncAvailable = true
        onLoadFailed: root.syncAvailable = false
        onFileChanged: reload()
    }

    property Process systemSync: Process {
        stdout: SplitParser {
            onRead: line => {
                const phases = {
                    "blankweave-theme-sync:folders": "Applying folder colors…",
                    "blankweave-theme-sync:boot-splash": "Applying boot appearance. Preparing the next boot may take a moment…",
                    "blankweave-theme-sync:console": "Applying boot console colors…",
                    "blankweave-theme-sync:complete": "Checking system appearance…"
                }
                if (phases[line]) {
                    root.syncStarted = true
                    root.syncState = "applying"
                    root.syncMessage = phases[line]
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && exitStatus === 0) {
                root.syncState = "verifying"
                root.syncMessage = "Checking system appearance…"
            } else if (!root.syncStarted && exitCode === 126 && exitStatus === 0) {
                root.syncState = "cancelled"
                root.syncMessage = "Authentication cancelled. System appearance wasn’t changed."
            } else {
                root.syncState = "error"
                root.syncMessage = !root.syncStarted && exitCode === 127
                    ? "Authentication could not be completed. Try again."
                    : "Couldn’t finish applying system appearance. Some changes may still be pending. Try again."
            }
            root.readStatus()
        }
    }
}
