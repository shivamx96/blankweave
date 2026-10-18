import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property string page: ""
    property string jobsHelper: Quickshell.env("HOME") + "/.local/share/blankweave/shell/operations-settings.py"
    property var reports: []
    property var trackedJobs: ({})
    property string jobsError: ""
    readonly property var backgroundJobs: reports.filter(job => trackedJobs[job.domain] === job.id
        && provider(job.domain) && provider(job.domain).dismissedJobId !== job.id)
    function refreshJobs() { if (page && !jobReader.running) jobReader.running = true }
    function trackJob(domain, id) {
        trackedJobs = Object.assign({}, trackedJobs, {[domain]: id})
        refreshJobs()
    }
    function ingestJobs(jobs) {
        let tracked = Object.assign({}, trackedJobs)
        for (const job of jobs) {
            if (["starting", "running"].includes(job.phase)) {
                tracked[job.domain] = job.id
                const task = provider(job.domain)
                if (task && (!task.ready || !task.data.job || task.data.job.id !== job.id)) task.refresh()
            }
        }
        trackedJobs = tracked
        reports = jobs
    }
    onPageChanged: refreshJobs()
    property Timer jobsPoll: Timer { interval: 2000; repeat: true; running: root.page !== ""; onTriggered: root.refreshJobs() }
    property Process jobReader: Process {
        command: ["python3", root.jobsHelper, "jobs"]
        stdout: StdioCollector { id: jobsOutput }
        stderr: StdioCollector { }
        onExited: (code, status) => {
            try {
                if (code || status) throw new Error("Task status is temporarily unavailable. Open its settings section to refresh.")
                const jobs = JSON.parse(jobsOutput.text)
                if (!Array.isArray(jobs)) throw new Error("Invalid task status response.")
                root.ingestJobs(jobs)
                root.jobsError = ""
            } catch (error) { root.jobsError = String(error) }
        }
    }
    property SettingsOperationTask vpnTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["vpn"]; active: root.page === "network"; onApplyFinished: (success, result) => { if (success && result && result.jobId) root.trackJob("vpn", result.jobId) } }
    property SettingsOperationTask sharingTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["sharing"]; active: root.page === "network"; onApplyFinished: (success, result) => { if (success && result && result.jobId) root.trackJob("sharing", result.jobId) } }
    property SettingsOperationTask hibernateTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["hibernate"]; active: root.page === "power"; onApplyFinished: (success, result) => { if (success && result && result.jobId) root.trackJob("hibernate", result.jobId) } }
    property SettingsOperationTask assistiveTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["assistive"]; active: root.page === "input"; onApplyFinished: (success, result) => { if (success && result && result.jobId) root.trackJob("assistive", result.jobId) } }
    property SettingsOperationTask installedTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["installed"]; active: root.page === "apps"; onApplyFinished: (success, result) => { if (success && result && result.jobId) root.trackJob("installed", result.jobId) } }
    property SettingsOperationTask permissionsTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["permissions"]; active: root.page === "apps"; onApplyFinished: (success, result) => { if (success && result && result.jobId) root.trackJob("permissions", result.jobId) } }
    property SettingsOperationTask disk_usageTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["disk-usage"]; active: root.page === "storage"; onApplyFinished: (success, result) => { if (success && result && result.jobId) root.trackJob("disk-usage", result.jobId) } }
    property SettingsOperationTask drivesTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["drives"]; active: root.page === "storage"; onApplyFinished: (success, result) => { if (success && result && result.jobId) root.trackJob("drives", result.jobId) } }
    property SettingsOperationTask disk_healthTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["disk-health"]; active: root.page === "storage"; onApplyFinished: (success, result) => { if (success && result && result.jobId) root.trackJob("disk-health", result.jobId) } }
    property SettingsOperationTask backupTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["backup"]; active: root.page === "storage"; onApplyFinished: (success, result) => { if (success && result && result.jobId) root.trackJob("backup", result.jobId) } }
    property SettingsOperationTask restoreTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["restore"]; active: root.page === "storage"; onApplyFinished: (success, result) => { if (success && result && result.jobId) root.trackJob("restore", result.jobId) } }
    property SettingsOperationTask snapshotsTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["snapshots"]; active: root.page === "storage"; onApplyFinished: (success, result) => { if (success && result && result.jobId) root.trackJob("snapshots", result.jobId) } }
    property SettingsOperationTask updatesTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["updates"]; active: root.page === "system"; onApplyFinished: (success, result) => { if (success && result && result.jobId) root.trackJob("updates", result.jobId) } }
    property SettingsOperationTask firmwareTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["firmware"]; active: root.page === "system"; onApplyFinished: (success, result) => { if (success && result && result.jobId) root.trackJob("firmware", result.jobId) } }
    property SettingsOperationTask accountsTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["accounts"]; active: root.page === "system"; onApplyFinished: (success, result) => { if (success && result && result.jobId) root.trackJob("accounts", result.jobId) } }
    property SettingsOperationTask datetimeTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["datetime"]; active: root.page === "system"; onApplyFinished: (success, result) => { if (success && result && result.jobId) root.trackJob("datetime", result.jobId) } }
    property SettingsOperationTask printersTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["printers"]; active: root.page === "system"; onApplyFinished: (success, result) => { if (success && result && result.jobId) root.trackJob("printers", result.jobId) } }
    function provider(id) { return ({"vpn": vpnTask, "sharing": sharingTask, "hibernate": hibernateTask, "assistive": assistiveTask, "installed": installedTask, "permissions": permissionsTask, "disk-usage": disk_usageTask, "drives": drivesTask, "disk-health": disk_healthTask, "backup": backupTask, "restore": restoreTask, "snapshots": snapshotsTask, "updates": updatesTask, "firmware": firmwareTask, "accounts": accountsTask, "datetime": datetimeTask, "printers": printersTask})[id] || null }
}
