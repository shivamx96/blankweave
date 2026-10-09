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
    readonly property bool ready: loaded && preferences.ready
    readonly property bool busy: listing.running || status.running || action.running

    function refresh() {
        if (busy) return
        operationError = ""
        listing.running = true
        status.running = true
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
                    root.systemPending = Boolean(value.system && value.system.pending)
                } catch (error) {
                    root.operationError = "Could not read theme status. Retry to refresh it."
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 || exitStatus !== 0)
                root.operationError = "Could not read theme status. Retry to refresh it."
        }
    }
    property Process action: Process {
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 || exitStatus !== 0)
                root.operationError = "The theme could not be fully applied. Retry or run blankweave theme status for details."
            root.status.running = true
        }
    }
}
