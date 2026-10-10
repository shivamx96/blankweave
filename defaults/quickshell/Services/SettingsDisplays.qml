import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property string helper: Quickshell.env("HOME") + "/.local/share/blankweave/shell/monitor-layout.sh"
    property bool active: false
    property var brightness: null
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
    readonly property bool canSelect: !busy && (!brightness || (!brightness.held && !brightness.busy))
    readonly property var monitor: monitors.find(row => row.name === selectedConnector) || null
    readonly property var scaleValues: monitor ? ["auto"].concat(monitor.scaleOptions) : []
    readonly property var positionValues: ["auto", "left", "right", "above", "below"]
    readonly property bool placeable: monitor !== null && !monitor.internal && monitors.length > 1
    readonly property string details: monitor
        ? monitor.width + " × " + monitor.height + " · Active scale " + percent(monitor.effectiveScale)
        : ""
    readonly property string savedScaleNotice: monitor && monitor.scale !== "auto"
        && Math.abs(Number(monitor.scale) - monitor.effectiveScale) > 0.000001
        ? "Saved scale " + percent(monitor.scale) + " is not active. Choose a scale to apply it again."
        : monitor && monitor.scale === "auto" ? "Automatic scaling follows your display’s pixel density." : ""

    function percent(value) { return Math.round(Number(value) * 10000) / 100 + "%" }
    function label(row) { return (row.internal ? "Built-in display" : row.description) + " · " + row.name }
    function choices(id) {
        if (id === "scale") return scaleValues.map(value => value === "auto" ? "Automatic" : percent(value))
        if (id === "arrangement") return ["Automatic", "Left", "Right", "Above", "Below"]
        return []
    }
    function canApply(id) {
        if (id === "brightness") return brightness !== null && brightness.available && brightness.active
        return (id === "scale" || (id === "arrangement" && placeable))
            && (!brightness || (!brightness.held && !brightness.busy))
    }
    function description(id) {
        if (id === "brightness") {
            if (!monitor) return "Select a connected display to adjust its brightness."
            if (!brightness || !brightness.loaded) return "Checking brightness support…"
            return brightness.error || (brightness.busy ? "Applying brightness…"
                : brightness.backend === "ddc" ? "Adjust this monitor using DDC/CI."
                : "Adjust the built-in backlight.")
        }
        if (id !== "arrangement") return ""
        if (!monitor) return "Select a connected display to choose its position."
        if (monitors.length < 2) return "Connect another display to change its position."
        if (monitor.internal) return "Select an external display to place it around the built-in display."
        return "Place this display around the existing desktop layout. Current origin: "
            + monitor.x + ", " + monitor.y + "."
    }
    function selection(id) {
        if (!monitor) return -1
        if (id === "arrangement") return positionValues.indexOf(monitor.position)
        if (id !== "scale") return -1
        // A saved numeric preference can differ from compositor state after a
        // failed apply or an external change. Show the actual scale in that case.
        return scaleValues.indexOf(monitor.scale === "auto" ? "auto" : monitor.effectiveScale)
    }
    function selectDisplay(index) {
        if (index >= 0 && index < monitors.length && canSelect)
            selectedConnector = monitors[index].name
    }
    function value(id) { return id === "brightness" && brightness ? brightness.percentage : -1 }
    function adjust(id, value) {
        if (id === "brightness" && ready && !busy && canApply(id)) brightness.queuePercentage(value)
    }
    function hold(id, pressed) { if (id === "brightness" && brightness) brightness.held = pressed }
    function refresh(includeBrightness = true) {
        if (applying || reading) return
        if (brightness && includeBrightness) brightness.refresh()
        reading = true
        status.running = true
    }
    function apply(id, index) {
        if (id === "brightness") {
            if (ready && !busy && canApply(id)) brightness.commitPercentage(index)
            return
        }
        if (!ready || busy || !canApply(id) || !Number.isInteger(index)
            || index < 0 || index >= choices(id).length) return
        operationError = ""
        applying = true
        action.command = id === "arrangement"
            ? ["bash", helper, "set", selectedConnector, positionValues[index]]
            : ["bash", helper, "set-scale", selectedConnector, String(scaleValues[index])]
        actionQueued = reading
        if (!reading) startAction()
    }
    function startAction() {
        const target = monitors.find(row => row.name === action.command[3])
        if (readError || !target || (action.command[2] === "set" && (target.internal || monitors.length < 2))) {
            applying = false
            operationError = "The connected displays changed. Select a display and try again."
            return
        }
        action.running = true
    }

    onActiveChanged: if (active) refresh()

    property Timer poll: Timer {
        interval: 2000
        running: root.active
        repeat: true
        onTriggered: root.refresh(false)
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
                        || !Number.isFinite(row.x) || !Number.isFinite(row.y)
                        || !root.positionValues.includes(row.position)
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
                root.startAction()
            }
        }
    }
    property Process action: Process {
        onExited: (exitCode, exitStatus) => {
            root.applying = false
            if (exitCode !== 0 || exitStatus !== 0)
                root.operationError = "Could not apply " + (action.command[2] === "set" ? "display position" : "scaling")
                    + ". The display may have disconnected or the setting may be unavailable. Refresh and try again."
            // Re-read even after failure: the helper may have saved the choice
            // before the compositor rejected it. Never claim it is active.
            root.refresh()
        }
    }
}
