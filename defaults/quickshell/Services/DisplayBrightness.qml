import QtQuick
import Quickshell
import Quickshell.Io

// Brightness state for one screen. The bar entry owns one of these for the
// screen it lives on and keeps it polling; the display panel instantiates one
// per other screen and polls those only while it is open, so a closed bar
// never spends DDC/CI round-trips on displays it is not showing.
Item {
    id: root

    required property var screen
    property bool active: true
    property int interval: 10000
    // Set by the slider that edits this display while it is being dragged,
    // so a poll that lands mid-drag cannot snap the handle back.
    property bool held: false

    readonly property string shellDir: Quickshell.env("HOME") + "/.local/share/blankweave/shell"
    readonly property string connector: String((screen && screen.name) || "")
    readonly property string reportedModel: String((screen && screen.model) || "")
    // The laptop panel is the anchor external displays are placed against,
    // so it is named for its role rather than its EDID model.
    readonly property bool internal: /^(eDP|LVDS|DSI)-/.test(connector)
    readonly property string displayName: internal
        ? "Built-in display"
        : (reportedModel === "LG HDR 4K"
            ? "LG UltraFine 27UL850"
            : (reportedModel || connector || "Display"))
    readonly property string backendName: backend === "ddc" ? "DDC/CI" : "Hardware backlight"
    readonly property bool available: confirmedPercentage >= 0

    property string helper: shellDir + "/brightness.sh"
    property int percentage: -1
    property int confirmedPercentage: -1
    property string backend: ""
    property bool loaded: false
    property bool reading: false
    property bool applying: false
    property int pendingPercentage: -1
    property int generation: 0
    property int readGeneration: -1
    property int applyGeneration: -1
    property int verificationTarget: -1
    property bool initialized: false
    property string readError: ""
    property string operationError: ""
    readonly property string error: operationError || readError
    readonly property bool busy: applying || pendingPercentage >= 0 || settleTimer.running || verificationTarget >= 0

    visible: false
    implicitWidth: 0
    implicitHeight: 0

    function resetDisplay() {
        generation++
        applyTimer.stop()
        settleTimer.stop()
        pendingPercentage = -1
        verificationTarget = -1
        percentage = -1
        confirmedPercentage = -1
        backend = ""
        loaded = false
        readError = ""
        operationError = ""
        refresh()
    }

    function queuePercentage(value) {
        if (!active || !connector || !available || !Number.isFinite(value)) return
        percentage = Math.max(5, Math.min(100, Math.round(value)))
        pendingPercentage = percentage
        operationError = ""
        settleTimer.stop()
        applyTimer.restart()
    }

    function commitPercentage(value) {
        queuePercentage(value)
        applyTimer.stop()
        applyPending()
    }

    function applyPending() {
        if (reading || applying || pendingPercentage < 0 || !active || !connector) return
        applyTimer.stop()
        settleTimer.stop()
        const wanted = pendingPercentage
        pendingPercentage = -1
        verificationTarget = wanted
        applyGeneration = generation
        applying = true
        applyProcess.command = ["bash", helper, "set", String(wanted), connector]
        applyProcess.running = true
    }

    function refresh() {
        if (!initialized || !active || !connector || reading || applying
            || pendingPercentage >= 0 || settleTimer.running || held) return
        readGeneration = generation
        reading = true
        readProcess.command = ["bash", helper, "status", connector]
        readProcess.running = true
    }

    Component.onCompleted: { initialized = true; resetDisplay() }
    onConnectorChanged: if (initialized) resetDisplay()
    onActiveChanged: {
        if (!initialized) return
        if (active) refresh()
        else {
            // Leave an already running command tied to its captured connector,
            // but discard a drag that has not yet reached the hardware.
            applyTimer.stop()
            settleTimer.stop()
            pendingPercentage = -1
            percentage = confirmedPercentage
        }
    }
    onHeldChanged: if (!held) refresh()

    Timer {
        interval: root.interval
        running: root.active && root.connector !== ""
        repeat: true
        onTriggered: root.refresh()
    }
    Timer {
        id: applyTimer
        interval: root.backend === "ddc" ? 150 : 50
        onTriggered: root.applyPending()
    }
    Process {
        id: readProcess
        stdout: StdioCollector { id: readOutput }
        onExited: (exitCode, exitStatus) => {
            root.reading = false
            if (root.readGeneration === root.generation) {
                root.loaded = true
                try {
                    if (exitCode !== 0 || exitStatus !== 0) throw new Error("Brightness read failed")
                    const status = JSON.parse(readOutput.text)
                    if (!Number.isFinite(status.percentage) || status.percentage < 0 || status.percentage > 100
                        || !["backlight", "ddc"].includes(status.backend) || status.connector !== root.connector)
                        throw new Error("Invalid brightness status")
                    root.confirmedPercentage = Math.round(status.percentage)
                    root.backend = status.backend
                    root.readError = ""
                    if (!root.held && root.pendingPercentage < 0) root.percentage = root.confirmedPercentage
                    if (root.verificationTarget >= 0 && root.pendingPercentage < 0) {
                        if (Math.abs(root.confirmedPercentage - root.verificationTarget) > 1)
                            root.operationError = "The display reports " + root.confirmedPercentage
                                + "% after requesting " + root.verificationTarget + "%. Try again."
                        root.verificationTarget = -1
                    }
                } catch (error) {
                    root.pendingPercentage = -1
                    root.verificationTarget = -1
                    applyTimer.stop()
                    root.percentage = -1
                    root.confirmedPercentage = -1
                    root.backend = ""
                    root.readError = root.internal
                        ? "Brightness is unavailable for this display. Refresh to retry."
                        : "Brightness is unavailable. Check the connection and enable DDC/CI in the monitor’s menu, then refresh."
                }
            }
            if (root.pendingPercentage >= 0) Qt.callLater(root.applyPending)
            else if (root.readGeneration !== root.generation) Qt.callLater(root.refresh)
        }
    }
    Process {
        id: applyProcess
        onExited: (exitCode, exitStatus) => {
            root.applying = false
            if (root.applyGeneration === root.generation) {
                if (exitCode !== 0 || exitStatus !== 0) {
                    root.operationError = "Could not change brightness. Check the display connection and try again."
                    root.verificationTarget = -1
                }
                if (root.pendingPercentage >= 0) Qt.callLater(root.applyPending)
                else if (root.active) settleTimer.restart()
            } else Qt.callLater(root.refresh)
        }
    }
    Timer {
        id: settleTimer
        interval: root.backend === "ddc" ? 900 : 300
        onTriggered: { stop(); root.refresh() }
    }
}
