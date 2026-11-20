import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // Shell-owned interface preferences: the small, scalar choices a widget
    // offers inside its own bar entry. Widget configuration with a real schema
    // and network work behind it keeps its own file and its own script instead
    // (see weather-status.sh), so every file has exactly one writer.
    //
    // Instantiate this once, in shell.qml, and reach it from a widget through
    // bar.shell.preferences. A second FileView over the same path would race
    // the first.
    //
    // The adapter below is the whole schema: anything missing from it is
    // dropped the next time the file is written, and an unreadable file falls
    // back to these defaults and is repaired by the next write.
    readonly property string directory: (Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")) + "/blankweave"

    // Writes wait for the first read to finish, so a preference changed while
    // the file is still loading cannot overwrite what is on disk with defaults.
    property bool ready: false
    property string writeError: ""
    property string confirmedHiddenWidgets: ""
    property bool widgetsPending: false
    function setWidgetVisibility(id, visible) {
        if (!ready || widgetsPending || ["overview", "power"].includes(id)) return
        const hidden = preferences.bar.hiddenWidgets.split(",").filter(Boolean)
        widgetsPending = true
        writeError = ""
        preferences.bar.hiddenWidgets = (visible ? hidden.filter(item => item !== id) : Array.from(new Set(hidden.concat([id])))).join(",")
    }


    function savePreferences() {
        if (root.ready) file.writeAdapter()
    }


    property FileView file: FileView {
        id: file

        path: root.directory + "/shell.json"
        watchChanges: true
        atomicWrites: true
        printErrors: false

        onLoaded: { root.ready = true; root.confirmedHiddenWidgets = preferences.bar.hiddenWidgets; root.widgetsPending = false }
        onLoadFailed: { root.ready = true }
        onSaved: { root.writeError = ""; if (root.widgetsPending) reload() }
        onSaveFailed: { root.widgetsPending = false; root.writeError = "Could not save bar preferences. Check access to the settings file." }
        onFileChanged: reload()
        onAdapterUpdated: {
            if (root.ready)
                Qt.callLater(root.savePreferences)
        }

        JsonAdapter {
            id: preferences

            property JsonObject clock: JsonObject {
                // 0 time, 1 date, 2 date and time.
                property int displayMode: 0
            }

            property JsonObject bar: JsonObject {
                // Shared by every screen so the shell keeps one consistent
                // edge and visibility policy across the desktop.
                property string position: "top"
                property string visibilityMode: "always"
                property string leftOrder: ""
                property string centerOrder: ""
                property string rightOrder: ""
                property string hiddenWidgets: ""
            }
        }
    }

    readonly property alias clock: preferences.clock
    readonly property alias bar: preferences.bar
}
