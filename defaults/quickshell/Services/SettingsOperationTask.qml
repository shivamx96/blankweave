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
    property string dismissedJobId: ""
    poll.running: root.active || root.draft.pending || Boolean(root.data.job && ["starting", "running"].includes(root.data.job.phase))
}
