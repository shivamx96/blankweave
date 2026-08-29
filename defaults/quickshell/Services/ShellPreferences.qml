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

    property FileView file: FileView {
        id: file

        path: root.directory + "/shell.json"
        watchChanges: true
        atomicWrites: true
        printErrors: false

        onLoaded: root.ready = true
        onLoadFailed: root.ready = true
        onFileChanged: reload()
        onAdapterUpdated: {
            if (root.ready)
                file.writeAdapter()
        }

        JsonAdapter {
            id: preferences

            property JsonObject clock: JsonObject {
                // 0 time, 1 date, 2 date and time.
                property int displayMode: 0
            }
        }
    }

    readonly property alias clock: preferences.clock
}
