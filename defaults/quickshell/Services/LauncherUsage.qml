import QtQuick
import Quickshell
import Quickshell.Io
import "LauncherUsage.js" as Usage

QtObject {
    id: root
    property var entries: DesktopEntries.applications ? DesktopEntries.applications.values : []
    readonly property var installedIds: entries.map(entry => String(entry.id))
    property var history: ({})
    property real referenceTime: Date.now()
    property bool ready: false
    property var queued: []
    property string writeError: ""
    property string path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/blankweave/launcher-usage.json"

    function prune() {
        if (!ready) return
        const next = Usage.clean(history, installedIds)
        if (JSON.stringify(next) !== JSON.stringify(history)) { history = next; save() }
    }
    onInstalledIdsChanged: prune()
    function save() { file.setText(JSON.stringify({version: 1, applications: history})) }
    function record(id) {
        if (!ready) { queued = queued.concat([id]); return }
        if (!installedIds.includes(id)) return
        const next = Object.assign({}, history)
        next[id] = {count: Math.min(1000000, (next[id] ? next[id].count : 0) + 1), last: Date.now()}
        history = Usage.clean(next, installedIds)
        save()
    }
    function finish() {
        ready = true
        prune()
        const pending = queued; queued = []
        pending.forEach(id => record(id))
    }
    property FileView file: FileView {
        path: root.path
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                const data = JSON.parse(text())
                root.history = data.version === 1 ? Usage.clean(data.applications, root.installedIds) : ({})
                // Persist pruning, including entries removed while the shell was down.
                root.finish()
                root.save()
            } catch (error) { root.history = ({}); root.finish() }
        }
        onLoadFailed: root.finish()
        onSaveFailed: root.writeError = "Could not save launcher usage."
        onSaved: root.writeError = ""
    }
}
