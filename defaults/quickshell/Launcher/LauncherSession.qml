import QtQuick

// Keep one logical invocation and one window, independent of pointer focus.
QtObject {
    id: root
    property var screens: []
    property string focusedScreenName: ""
    property bool open: false
    property string mode: "applications"
    property string searchText: ""
    property int selectedIndex: 0
    signal refreshRequested
    property string targetName: ""
    readonly property var targetScreen: {
        for (const screen of screens) {
            if (screen.name === targetName) return screen
        }
        return null
    }

    function chooseTarget() {
        for (const screen of screens) {
            if (screen.name === focusedScreenName) return screen.name
        }
        return screens.length ? screens[0].name : ""
    }

    function toggle(nextMode) {
        if (open && mode === nextMode) {
            open = false
            return
        }
        if (!open) targetName = chooseTarget()
        mode = nextMode
        open = true
    }

    function dismiss() { open = false }

    function refresh() {
        searchText = ""
        selectedIndex = 0
        refreshRequested()
    }
    onOpenChanged: if (open) refresh()
    onModeChanged: if (open) refresh()

    onScreensChanged: {
        // Latch the fallback too: reconnecting the old display must not move
        // an in-progress search back again. Zero outputs temporarily hides it.
        let connected = false
        for (const screen of screens) {
            if (screen.name === targetName) connected = true
        }
        if (open && !connected) targetName = chooseTarget()
    }
}
