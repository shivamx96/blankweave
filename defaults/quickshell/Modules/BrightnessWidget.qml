import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../Components"
import "../Services"

WidgetFrame {
    id: root

    readonly property string shellDir: Quickshell.env("HOME") + "/.local/share/hyprarch/shell"

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
            if (open)
                placementPoller.refresh()
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
                    root.bar.run([root.shellDir + "/theme-toggle.sh"])
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
    }

    Timer {
        id: themeCloseGuard
        interval: 1800
        onTriggered: brightnessPanel.preserveNextClose = false
    }
}
