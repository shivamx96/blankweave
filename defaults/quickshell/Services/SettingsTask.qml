import QtQuick
import Quickshell
import Quickshell.Io
import "SettingsOutcome.js" as Outcomes

QtObject {
    id: root
    required property string script
    property string helper: Quickshell.env("HOME") + "/.local/share/blankweave/shell/" + script
    property var arguments: []
    property bool active: false
    property bool ready: false
    property bool writing: false
    property string error: ""
    property string errorDetail: ""
    property bool cancelled: false
    property var outcomes: ({})
    property var outcomeVersions: ({})
    property int pendingVersion: 0
    property var pendingRequest: ({})
    property var pendingBaseline: ({})
    property string notice: ""
    function outcome(action, target = "") {
        return outcomes[JSON.stringify([action, target])] || null
    }
    function clearOutcome(action, target = "") {
        const key = JSON.stringify([action, target])
        const versions = Object.assign({}, outcomeVersions)
        versions[key] = (versions[key] || 0) + 1
        outcomeVersions = versions
        const next = Object.assign({}, outcomes)
        delete next[key]
        outcomes = next
        if (feedbackTarget === JSON.stringify([action, target])) { error = ""; errorDetail = ""; cancelled = false }
    }
    function failure(output) {
        if ((outcomeVersions[feedbackTarget] || 0) !== pendingVersion) return
        let value = null
        try { value = JSON.parse(output).error } catch (_) {}
        error = value && typeof value.message === "string" ? value.message : "Could not apply this change. Try again."
        errorDetail = value && typeof value.detail === "string" ? value.detail : ""
        cancelled = Boolean(value && value.cancelled)
        const next = Object.assign({}, outcomes)
        next[feedbackTarget] = {message: error, detail: errorDetail, cancelled: cancelled,
            field: value ? value.field || "" : "", request: pendingRequest, baseline: pendingBaseline,
            expires: cancelled ? Date.now() + 2500 : 0}
        outcomes = next
    }
    function reconcile(value) {
        const next = Object.assign({}, outcomes)
        for (const key of Object.keys(next)) {
            const entry = next[key]
            const match = Outcomes.observed(script, entry.request, value, entry.baseline)
            if (match === true || (match === null && JSON.stringify(value) !== JSON.stringify(entry.baseline))) {
                delete next[key]
                if (key === feedbackTarget) { error = ""; errorDetail = ""; cancelled = false }
            }
        }
        outcomes = next
    }
    property Timer cancellationTimer: Timer {
        interval: 100; repeat: true; running: Object.values(root.outcomes).some(e => e.cancelled)
        onTriggered: {
            const next = Object.assign({}, root.outcomes)
            for (const key of Object.keys(next)) {
                if (next[key].expires && next[key].expires <= Date.now()) {
                    delete next[key]
                    if (key === root.feedbackTarget) { root.error = ""; root.errorDetail = ""; root.cancelled = false }
                }
            }
            root.outcomes = next
        }
    }
    property var data: ({})
    property string request: ""
    property string feedbackTarget: ""
    signal applyFinished(bool success, var result)
    readonly property bool busy: writing || status.running || action.running
    readonly property bool writable: ready && !busy && data.writable !== false
    function refresh(clearError = false) {
        if (busy) return
        status.running = true
    }
    function apply(options, revision, control) {
        if (!writable) return
        options = Object.assign({}, options)
        if (control) options.control = control
        feedbackTarget = Outcomes.key(options)
        clearOutcome(options.control || options.action || "value", options.id || options.app || "")
        pendingVersion = outcomeVersions[feedbackTarget] || 0
        pendingRequest = Outcomes.capture(script, options)
        pendingBaseline = JSON.parse(JSON.stringify(data))
        const payload = Object.assign({}, options, {revision: revision || data.revision})
        delete payload.control
        request = JSON.stringify(payload)
        writing = true; error = ""; errorDetail = ""; cancelled = false; action.running = true
    }
    function cancelJob(id) {
        if (busy) return
        pendingRequest = {action: "cancel-job", id: id}
        pendingBaseline = JSON.parse(JSON.stringify(data))
        feedbackTarget = Outcomes.key(pendingRequest)
        clearOutcome("cancel-job", id)
        pendingVersion = outcomeVersions[feedbackTarget] || 0
        request = JSON.stringify(pendingRequest)
        writing = true; error = ""; errorDetail = ""; cancelled = false; action.running = true
    }
    onActiveChanged: if (active) refresh(true)
    property Timer poll: Timer { interval: 5000; repeat: true; running: root.active; onTriggered: root.refresh() }
    property Process status: Process {
        command: ["python3", root.helper].concat(root.arguments, ["status"])
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: readError }
        onExited: (code, exitStatus) => {
            try {
                if (code || exitStatus) throw new Error(readError.text.trim() || "Could not read settings.")
                const value = JSON.parse(output.text)
                if (!value || typeof value.revision !== "string") throw new Error("Invalid settings response.")
                root.reconcile(value)
                root.notice = ""
                root.data = value; root.ready = true
            } catch (failure) { root.ready = false; root.notice = "Could not read settings. Try again." }
        }
    }
    property Process action: Process {
        command: ["python3", root.helper].concat(root.arguments, ["apply"])
        stdinEnabled: true
        onStarted: { write(root.request); root.request = ""; stdinEnabled = false }
        stderr: StdioCollector { id: writeError }
        stdout: StdioCollector { id: writeResult }
        onExited: (code, exitStatus) => {
            root.writing = false; stdinEnabled = true
            if (code || exitStatus) root.failure(writeResult.text)
            else { root.error = ""; root.errorDetail = "" }
            let result = null
            try { result = JSON.parse(writeResult.text) } catch (_) { }
            root.applyFinished(!code && !exitStatus, result)
            Qt.callLater(() => root.refresh())
        }
    }
}
