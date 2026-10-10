import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property string helper: Quickshell.env("HOME") + "/.local/share/blankweave/shell/monitor-layout.sh"
    property bool active: false
    property var brightness: null
    property var monitors: []
    property var presets: []
    property string selectedConnector: ""
    property bool loaded: false
    property string readError: ""
    property string operationError: ""
    property bool reading: false
    property bool applying: false
    property bool actionQueued: false
    property bool revertWhenHidden: false
    property var preview: null
    property double now: Date.now() / 1000
    readonly property int previewSeconds: preview ? Math.max(0, Math.ceil(preview.deadline - now)) : 0
    readonly property bool previewPending: preview !== null
    readonly property string previewMessage: preview && preview.kind === "layout"
        ? preview.label + "? Reverting in " + previewSeconds + " seconds."
        : preview ? "Keep " + preview.mode.replace("x", " × ").replace("@", " · ")
        + " Hz on " + preview.connector + "? Reverting in " + previewSeconds + " seconds." : ""
    readonly property string error: operationError || readError
    // Background reads must not disable an open menu every polling interval.
    readonly property bool busy: applying || previewPending || (!loaded && reading)
    readonly property bool ready: loaded && readError === "" && monitor !== null
    readonly property bool canSelect: !busy && (!brightness || (!brightness.held && !brightness.busy))
    readonly property var monitor: monitors.find(row => row.name === selectedConnector) || null
    readonly property var scaleValues: monitor ? ["auto"].concat(monitor.scaleOptions) : []
    readonly property var modeValues: monitor ? (monitor.modeOptions || []) : []
    readonly property var positionValues: ["auto", "left", "right", "above", "below", "custom"]
    readonly property bool mirrored: monitor !== null && Boolean(monitor.mirrorConnector)
    readonly property var mirrorSources: monitor && !monitors.some(row => row.mirrorConnector === monitor.name)
        ? monitors.filter(row => row.name !== monitor.name && !row.mirrorConnector) : []
    readonly property var mirrorValues: ["none"].concat(mirrorSources.map(row => row.name))
    readonly property bool placeable: monitor !== null && !mirrored && !monitor.internal && monitors.length > 1
    readonly property string details: monitor
        ? monitor.width + " × " + monitor.height + (monitor.refreshRate ? " · " + Number(monitor.refreshRate.toFixed(2)) + " Hz" : "") + " · Active scale " + percent(monitor.effectiveScale)
        : ""
    readonly property string savedScaleNotice: monitor && monitor.scale !== "auto"
        && Math.abs(Number(monitor.scale) - monitor.effectiveScale) > 0.000001
        ? "Saved scale " + percent(monitor.scale) + " is not active. Choose a scale to apply it again."
        : monitor && monitor.scale === "auto" ? "Automatic scaling follows your display’s pixel density." : ""

    function percent(value) { return Math.round(Number(value) * 10000) / 100 + "%" }
    function label(row) { return (row.internal ? "Built-in display" : row.description) + " · " + row.name }
    function choices(id) {
        if (id === "mirroring") return ["Extend desktop"].concat(mirrorSources.map(row => "Mirror " + row.name))
        if (id === "resolution") return modeValues.map(mode => mode.replace("x", " × ").replace("@", " · ") + " Hz")
        if (id === "scale") return scaleValues.map(value => value === "auto" ? "Automatic" : percent(value))
        if (id === "arrangement") return ["Automatic", "Left", "Right", "Above", "Below"].concat(monitor && monitor.position === "custom" ? ["Saved coordinates"] : [])
        return []
    }
    function canApply(id) {
        if (id === "brightness") return brightness !== null && brightness.available && brightness.active
        return (id === "display-presets" || (id === "mirroring" && (mirrored || mirrorSources.length > 0))
            || (!mirrored && (id === "scale" || (id === "resolution" && modeValues.length > 0) || (id === "arrangement" && placeable))))
            && (!brightness || (!brightness.held && !brightness.busy))
    }
    function description(id) {
        if (id === "mirroring") {
            if (monitors.length < 2) return "Connect another display to mirror its content."
            if (mirrored) return "Showing " + monitor.mirrorConnector + ". Choose Extend desktop for a separate workspace."
            if (mirrorSources.length === 0) return "This display is a mirror source. Extend its mirrors before changing its source."
            return "Show another display’s content here. Keep the change within 20 seconds."
        }
        if (mirrored && ["scale", "resolution", "arrangement"].includes(id))
            return "Choose Extend desktop before adjusting this mirrored display."

        if (id === "resolution") return modeValues.length
            ? "Try a supported mode, then keep it within 20 seconds. Scaling adjusts if needed."
            : "This display does not report supported modes."
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
        if (id === "mirroring") return mirrorValues.indexOf(monitor.mirrorConnector || "none")
        if (id === "resolution") return modeValues.findIndex(mode => {
            const parts = mode.split(/[x@]/)
            return Number(parts[0]) === monitor.width && Number(parts[1]) === monitor.height
                && Math.abs(Number(parts[2]) - monitor.refreshRate) < 0.006
        })
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
        if (id === "arrangement" && positionValues[index] === "custom") return
        operationError = ""
        applying = true
        action.command = id === "arrangement"
            ? ["bash", helper, "set", selectedConnector, positionValues[index]]
            : id === "mirroring" ? ["bash", helper, "mirror-preview", selectedConnector, mirrorValues[index]]
            : id === "resolution" ? ["bash", helper, "mode-preview", selectedConnector, modeValues[index]]
            : ["bash", helper, "set-scale", selectedConnector, String(scaleValues[index])]
        actionQueued = reading
        if (!reading) startAction()
    }
    function savePreset(name) { presetAction("preset-save", name.trim()) }
    function restorePreset(id) {
        if (presets.some(row => row.id === id && row.available)) presetAction("preset-preview", id)
    }
    function deletePreset(id) {
        if (presets.some(row => row.id === id)) presetAction("preset-delete", id)
    }
    function presetAction(command, value) {
        if (!ready || busy || !canApply("display-presets") || !value) return
        operationError = ""
        applying = true
        action.command = ["bash", helper, command, value]
        actionQueued = reading
        if (!reading) startAction()
    }
    function startAction() {
        if (action.command[2] === "mode-confirm" || action.command[2] === "mode-revert"
            || action.command[2].startsWith("preset-")) {
            action.running = true
            return
        }
        const target = monitors.find(row => row.name === action.command[3])
        if (readError || !target || (action.command[2] === "set" && (target.internal || monitors.length < 2))) {
            applying = false
            operationError = "The connected displays changed. Select a display and try again."
            return
        }
        action.running = true
    }

    function finishPreview(keep) {
        if (!preview || applying || (keep && previewSeconds <= 0)) return
        revertWhenHidden = false
        operationError = ""
        applying = true
        action.command = ["bash", helper, keep ? "mode-confirm" : "mode-revert", preview.token]
        actionQueued = reading
        if (!reading) startAction()
    }

    onActiveChanged: {
        if (active) { revertWhenHidden = false; refresh() }
        else { revertWhenHidden = true; finishPreview(false) }
    }

    property Timer countdown: Timer {
        interval: 250
        running: root.previewPending
        repeat: true
        onTriggered: root.now = Date.now() / 1000
    }

    property Timer poll: Timer {
        interval: 2000
        running: root.active || root.previewPending
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
                if (value.preview != null && (typeof value.preview.token !== "string"
                    || typeof value.preview.connector !== "string" || typeof value.preview.mode !== "string"
                    || !Number.isFinite(value.preview.deadline)
                    || (value.preview.kind === "layout" && typeof value.preview.label !== "string"))) throw new Error("Invalid preview")
                if (value.presets !== undefined && (!Array.isArray(value.presets)
                    || !value.presets.every(row => row && typeof row.id === "string" && typeof row.name === "string"
                        && typeof row.available === "boolean" && typeof row.reason === "string" && typeof row.summary === "string")))
                    throw new Error("Invalid saved setups")
                if (JSON.stringify(root.presets) !== JSON.stringify(value.presets || []))
                    root.presets = value.presets || []
                root.preview = value.preview || null
                root.now = Date.now() / 1000
                const names = []
                for (const row of value.monitors) {
                    if (!row || typeof row.name !== "string" || !row.name || names.includes(row.name)
                        || (row.mirrorConnector !== undefined && typeof row.mirrorConnector !== "string")
                        || typeof row.description !== "string" || typeof row.internal !== "boolean"
                        || !Number.isFinite(row.width) || row.width <= 0
                        || !Number.isFinite(row.height) || row.height <= 0
                        || !Number.isFinite(row.x) || !Number.isFinite(row.y)
                        || !root.positionValues.includes(row.position)
                        || !Number.isFinite(row.effectiveScale) || row.effectiveScale <= 0
                        || !(row.scale === "auto" || (Number.isFinite(row.scale) && row.scale > 0))
                        || (row.modeOptions !== undefined && (!Array.isArray(row.modeOptions)
                            || !row.modeOptions.every(mode => typeof mode === "string" && /^[0-9]+x[0-9]+@[0-9]+(\.[0-9]+)?$/.test(mode))
                            || !Number.isFinite(row.refreshRate) || row.refreshRate < 0))
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
            } else if (root.revertWhenHidden && root.previewPending) {
                root.finishPreview(false)
            }
        }
    }
    property Process action: Process {
        stderr: StdioCollector { id: actionError }
        onExited: (exitCode, exitStatus) => {
            root.applying = false
            if (exitCode !== 0 || exitStatus !== 0)
                root.operationError = actionError.text.trim() || "Could not apply " + (action.command[2] === "set" ? "display position"
                        : action.command[2] === "set-scale" ? "scaling" : "the display mode")
                    + ". The display may have disconnected or the setting may be unavailable. Refresh and try again."
            // Re-read even after failure: the helper may have saved the choice
            // before the compositor rejected it. Never claim it is active.
            root.refresh()
        }
    }
}
