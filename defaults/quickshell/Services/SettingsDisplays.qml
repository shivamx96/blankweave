import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property string helper: Quickshell.env("HOME") + "/.local/share/blankweave/shell/monitor-layout.sh"
    property bool active: false
    property var monitors: []
    property string selectedConnector: ""
    property bool loaded: false
    property string readError: ""
    property string operationError: ""
    property bool reading: false
    property bool applying: false
    property bool actionQueued: false
    readonly property string error: operationError || readError
    // Background reads must not disable an open menu every polling interval.
    readonly property bool busy: applying || (!loaded && reading)
    readonly property bool ready: loaded && readError === "" && monitor !== null
    readonly property var monitor: monitors.find(row => row.name === selectedConnector) || null
    readonly property var scaleValues: monitor ? ["auto"].concat(monitor.scaleOptions) : []
    readonly property string details: monitor
        ? monitor.width + " × " + monitor.height + " · Active scale " + percent(monitor.effectiveScale)
        : ""
    readonly property string savedScaleNotice: monitor && monitor.scale !== "auto"
        && Math.abs(Number(monitor.scale) - monitor.effectiveScale) > 0.000001
        ? "Saved scale " + percent(monitor.scale) + " is not active. Choose a scale to apply it again."
        : monitor && monitor.scale === "auto" ? "Automatic scaling follows your display’s pixel density." : ""

    function percent(value) { return Math.round(Number(value) * 10000) / 100 + "%" }
    function label(row) { return (row.internal ? "Built-in display" : row.description) + " · " + row.name }
    function choices(id) { return id === "scale" ? scaleValues.map(value => value === "auto" ? "Automatic" : percent(value)) : [] }
    function selection(id) {
        if (id !== "scale" || !monitor) return -1
        // A saved numeric preference can differ from compositor state after a
        // failed apply or an external change. Show the actual scale in that case.
        return scaleValues.indexOf(monitor.scale === "auto" ? "auto" : monitor.effectiveScale)
    }
    function selectDisplay(index) {
        if (index >= 0 && index < monitors.length && !applying)
            selectedConnector = monitors[index].name
    }
    function refresh() {
        if (applying || reading) return
        reading = true
        status.running = true
    }
    function apply(id, index) {
        if (id !== "scale" || !ready || busy || index < 0 || index >= scaleValues.length) return
        operationError = ""
        applying = true
        action.command = ["bash", helper, "set-scale", selectedConnector, String(scaleValues[index])]
        actionQueued = reading
        if (!reading) action.running = true
    }

    onActiveChanged: if (active) refresh()

    property Timer poll: Timer {
        interval: 2000
        running: root.active
        repeat: true
        onTriggered: root.refresh()
    }
    property Process status: Process {
        command: ["bash", root.helper, "status"]
        stdout: StdioCollector { id: statusOutput }
        onExited: (exitCode, exitStatus) => {
            root.reading = false
            root.loaded = true
            try {
                if (exitCode !== 0 || exitStatus !== 0) throw new Error("Status failed")
                const value = JSON.parse(statusOutput.text)
                if (!Array.isArray(value.monitors)) throw new Error("Invalid monitor list")
                const names = []
                for (const row of value.monitors) {
                    if (!row || typeof row.name !== "string" || !row.name || names.includes(row.name)
                        || typeof row.description !== "string" || typeof row.internal !== "boolean"
                        || !Number.isFinite(row.width) || row.width <= 0
                        || !Number.isFinite(row.height) || row.height <= 0
                        || !Number.isFinite(row.effectiveScale) || row.effectiveScale <= 0
                        || !(row.scale === "auto" || (Number.isFinite(row.scale) && row.scale > 0))
                        || !Array.isArray(row.scaleOptions) || !row.scaleOptions.includes(row.effectiveScale)
                        || !row.scaleOptions.every(scale => Number.isFinite(scale) && scale > 0))
                        throw new Error("Invalid monitor")
                    names.push(row.name)
                }
                if (JSON.stringify(root.monitors) !== JSON.stringify(value.monitors))
                    root.monitors = value.monitors
                if (!names.includes(root.selectedConnector))
                    root.selectedConnector = names[0] || ""
                root.readError = ""
            } catch (error) {
                root.monitors = []
                root.readError = "Could not read connected displays. Check your desktop connection and refresh."
            }
            if (root.actionQueued) {
                root.actionQueued = false
                // The helper revalidates the captured connector and scale
                // against live state before writing, including after hotplug.
                root.action.running = true
            }
        }
    }
    property Process action: Process {
        onExited: (exitCode, exitStatus) => {
            root.applying = false
            if (exitCode !== 0 || exitStatus !== 0)
                root.operationError = "Could not apply scaling. The display may have disconnected or the setting may be unavailable. Refresh and try again."
            // Re-read even after failure: the helper may have saved the choice
            // before the compositor rejected it. Never claim it is active.
            root.refresh()
        }
    }
}
