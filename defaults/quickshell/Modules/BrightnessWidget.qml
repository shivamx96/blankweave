import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../Components"
import "../Services"

WidgetFrame {
    id: root

    readonly property string shellDir: Quickshell.env("HOME") + "/.local/share/blankweave/shell"

    // The bar entry is about the screen it is drawn on; the panel covers
    // every screen, this one first.
    readonly property DisplayBrightness display: ownDisplay
    readonly property var otherScreens: {
        // The bar's screen is cleared before the bar itself is torn down.
        const own = root.bar.screen
        if (!own)
            return []
        const screens = Quickshell.screens
        const others = []
        for (let index = 0; index < screens.length; index++) {
            if (screens[index] !== own && screens[index].name !== own.name)
                others.push(screens[index])
        }
        return others
    }
    property var displays: [ownDisplay]

    // Arrangement, keyed by connector, from monitor-layout.sh. Read when the
    // panel opens and after every change; the script owns the persisted file.
    property var placements: ({})
    property string pendingPlacementConnector: ""
    property string pendingPlacementPosition: ""
    readonly property var positionChoices: [
        { "id": "left", "label": "Left" },
        { "id": "right", "label": "Right" },
        { "id": "above", "label": "Above" },
        { "id": "below", "label": "Below" },
        { "id": "auto", "label": "Auto" }
    ]

    // What an external display's position is relative to: the built-in panel
    // when there is one, otherwise whatever else is already laid out.
    readonly property string placementAnchor: {
        for (let index = 0; index < root.displays.length; index++) {
            if (root.displays[index].internal)
                return root.displays[index].displayName
        }
        return "other displays"
    }

    // Themes come from theme-apply.sh, the one writer of the selection; the
    // rows are primitive snapshots of its `list` output. `status` says whether
    // the root-only parts (folder colours, boot splash) still need a sync.
    property var themes: []
    property string pendingThemeId: ""
    property bool systemPending: false

    function themeSwatch(row) {
        const modes = Array.isArray(row.modes) ? row.modes : []
        const wanted = root.theme.mode
        for (let index = 0; index < modes.length; index++) {
            if (String(modes[index].mode) === wanted && modes[index].accent)
                return root.theme.cssColor(String(modes[index].accent))
        }
        return null
    }

    function setTheme(themeId) {
        if (themeProcess.running || themeId === root.theme.themeId)
            return

        root.pendingThemeId = themeId
        brightnessPanel.preserveNextClose = true
        themeCloseGuard.restart()
        themeProcess.command = [root.shellDir + "/theme-apply.sh", "set", themeId]
        themeProcess.running = true
    }

    function placementFor(connector) {
        return root.placements[connector] || null
    }

    function setPlacement(connector, position) {
        if (placementProcess.running)
            return

        root.pendingPlacementConnector = connector
        root.pendingPlacementPosition = position
        placementProcess.command = [root.shellDir + "/monitor-layout.sh", "set", connector, position]
        placementProcess.running = true
    }

    function syncDisplays() {
        const list = [ownDisplay]
        for (let index = 0; index < otherDisplays.count; index++)
            list.push(otherDisplays.objectAt(index))
        root.displays = list
    }

    visible: display.available
    icon: display.percentage < 34 ? "󰃞" : (display.percentage < 67 ? "󰃟" : "󰃠")
    iconPixelSize: theme.barIconSize - 2
    label: display.available ? display.percentage + "%" : ""
    tooltip: display.available
        ? display.displayName + ": " + display.percentage + "%\nClick for controls · Scroll to adjust"
        : ""

    DisplayBrightness {
        id: ownDisplay
        screen: root.bar.screen
    }

    Instantiator {
        id: otherDisplays
        model: root.otherScreens
        delegate: DisplayBrightness {
            required property var modelData
            screen: modelData
            active: brightnessPanel.open
        }
        onObjectAdded: (index, object) => root.syncDisplays()
        onObjectRemoved: (index, object) => root.syncDisplays()
    }

    ScriptPoller {
        id: placementPoller
        command: root.shellDir + "/monitor-layout.sh status"
        interval: 0
        onUpdated: payload => {
            const next = {}
            try {
                const status = JSON.parse(payload)
                const monitors = Array.isArray(status.monitors) ? status.monitors : []
                for (let index = 0; index < monitors.length; index++)
                    next[String(monitors[index].name || "")] = monitors[index]
            } catch (error) {
            }
            root.placements = next
        }
    }

    Process {
        id: placementProcess

        onExited: {
            root.pendingPlacementConnector = ""
            root.pendingPlacementPosition = ""
            placementPoller.refresh()
        }
    }

    ScriptPoller {
        id: themePoller
        command: root.shellDir + "/theme-apply.sh list"
        interval: 0
        onUpdated: payload => {
            const rows = []
            try {
                const listing = JSON.parse(payload)
                const entries = Array.isArray(listing) ? listing : []
                for (let index = 0; index < entries.length; index++) {
                    if (entries[index].invalid)
                        continue
                    rows.push({
                        "id": String(entries[index].id || ""),
                        "name": String(entries[index].name || entries[index].id || ""),
                        "modes": Array.isArray(entries[index].modes) ? entries[index].modes : []
                    })
                }
            } catch (error) {
            }
            root.themes = rows
        }
    }

    ScriptPoller {
        id: themeStatusPoller
        command: root.shellDir + "/theme-apply.sh status"
        interval: 0
        onUpdated: payload => {
            let pending = false
            try {
                const status = JSON.parse(payload)
                pending = Boolean(status.system && status.system.pending)
            } catch (error) {
            }
            root.systemPending = pending
        }
    }

    Process {
        id: themeProcess

        onExited: {
            root.pendingThemeId = ""
            themeStatusPoller.refresh()
        }
    }

    onPressed: button => {
        if (button === Qt.LeftButton) {
            root.bar.hideTooltip(root)
            brightnessPanel.open = !brightnessPanel.open
        }
    }

    onScrolled: delta => {
        if (display.available)
            display.queuePercentage(display.percentage + (delta > 0 ? 2 : -2))
    }

    ControlPopup {
        id: brightnessPanel
        bar: root.bar
        theme: root.theme
        anchorItem: root

        onOpenChanged: {
            if (open) {
                placementPoller.refresh()
                themePoller.refresh()
                themeStatusPoller.refresh()
            }
        }

        ControlPanelHeader {
            theme: root.theme
            icon: "󰃠"
            title: "DISPLAY"
            subtitle: root.displays.length > 1
                ? root.displays.length + " displays"
                : root.display.displayName + " · " + root.display.backendName
            actions: [
                { "id": "theme", "icon": root.theme.dark ? "󰖙" : "󰖔" }
            ]
            onActionPressed: actionId => {
                if (actionId === "theme") {
                    brightnessPanel.preserveNextClose = true
                    themeCloseGuard.restart()
                    root.bar.run([root.shellDir + "/theme-apply.sh", "toggle"])
                }
            }
        }

        Repeater {
            model: root.displays

            delegate: ColumnLayout {
                id: displayRow

                required property var modelData
                readonly property var placement: root.placementFor(displayRow.modelData.connector)
                // Only an external display is placed; the internal panel is
                // what it is placed against, and a lone display has nowhere
                // to go.
                readonly property bool placeable: root.displays.length > 1
                    && placement !== null
                    && !placement.internal
                readonly property bool placing: root.pendingPlacementConnector === displayRow.modelData.connector
                readonly property string currentPosition: placing
                    ? root.pendingPlacementPosition
                    : String((placement && placement.position) || "auto")

                Layout.fillWidth: true
                spacing: 10
                visible: modelData.available || placeable

                ControlSectionLabel {
                    theme: root.theme
                    text: root.displays.length > 1
                        ? displayRow.modelData.displayName.toUpperCase()
                            + (displayRow.modelData.available ? " · " + displayRow.modelData.backendName.toUpperCase() : "")
                        : "BRIGHTNESS"
                }

                ControlValueRow {
                    id: brightnessControl
                    visible: displayRow.modelData.available
                    theme: root.theme
                    from: 5
                    to: 100
                    value: displayRow.modelData.percentage
                    stepSize: 1
                    valueText: displayRow.modelData.percentage + "%"
                    onValueMoved: value => displayRow.modelData.queuePercentage(value)
                    onValueCommitted: value => displayRow.modelData.commitPercentage(value)
                }

                Binding {
                    target: displayRow.modelData
                    property: "held"
                    value: brightnessControl.pressed
                }

                ControlSectionLabel {
                    visible: displayRow.placeable
                    theme: root.theme
                    text: "POSITION RELATIVE TO " + root.placementAnchor.toUpperCase()
                }

                RowLayout {
                    visible: displayRow.placeable
                    Layout.fillWidth: true
                    spacing: 5

                    Repeater {
                        model: root.positionChoices

                        delegate: ControlChoice {
                            required property var modelData

                            Layout.fillWidth: true
                            theme: root.theme
                            text: String(modelData.label)
                            selected: displayRow.currentPosition === String(modelData.id)
                            busy: displayRow.placing && displayRow.currentPosition === String(modelData.id)
                            enabled: !placementProcess.running
                            onPressed: root.setPlacement(displayRow.modelData.connector, String(modelData.id))
                        }
                    }
                }
            }
        }

        ControlSectionLabel {
            visible: root.themes.length > 0
            theme: root.theme
            text: "THEME · " + root.theme.mode.toUpperCase()
        }

        Flow {
            visible: root.themes.length > 0
            Layout.fillWidth: true
            spacing: 5

            Repeater {
                model: root.themes

                delegate: ControlChoice {
                    required property var modelData

                    theme: root.theme
                    text: String(modelData.name)
                    swatch: root.themeSwatch(modelData)
                    selected: root.theme.themeId === String(modelData.id)
                    busy: root.pendingThemeId === String(modelData.id)
                    enabled: !themeProcess.running
                    onPressed: root.setTheme(String(modelData.id))
                }
            }
        }

        Text {
            visible: root.systemPending
            Layout.fillWidth: true
            text: "Folder colours and boot splash follow on blankweave theme sync"
            color: root.theme.textMuted
            wrapMode: Text.WordWrap
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.microTextSize
            renderType: Text.NativeRendering
        }
    }

    Timer {
        id: themeCloseGuard
        interval: 1800
        onTriggered: brightnessPanel.preserveNextClose = false
    }
}
