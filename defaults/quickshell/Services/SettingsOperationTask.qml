import QtQuick

SettingsTask {
    id: root
    property var jobOutcomes: ({})
    function outcome(action, target = "") {
        const key = JSON.stringify([action, target])
        return jobOutcomes[key] || outcomes[key] || null
    }
    onWritingChanged: if (writing && pendingRequest.action) {
        const next = Object.assign({}, jobOutcomes)
        delete next[JSON.stringify([pendingRequest.action, ""])]
        jobOutcomes = next
    }
    readonly property SettingsOperationDraft draft: SettingsOperationDraft { backend: root }
    status.command: ["env", "BLANKWEAVE_STORAGE_VISIBLE=" + (root.active ? "1" : "0"), "python3", root.helper].concat(root.arguments, ["status"])
    onActiveChanged: {
        if (active) refresh(true)
        if (!active && arguments[0] === "disk-usage") status.running = false
    }
    function launchUpdate() {
        // The service injects the shared launcher callback.
        if (terminalLauncher) terminalLauncher()
    }
    property var terminalLauncher: null
    property string dismissedJobId: ""
    poll.running: root.active || root.draft.pending || Boolean(root.data.job && ["starting", "running"].includes(root.data.job.phase))
}
