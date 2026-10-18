import QtQuick

SettingsTask {
    id: root
    readonly property SettingsOperationDraft draft: SettingsOperationDraft { backend: root }
    property string dismissedJobId: ""
    poll.running: root.active || root.draft.pending || Boolean(root.data.job && ["starting", "running"].includes(root.data.job.phase))
}
