import QtQuick

QtObject {
    id: root
    property string page: ""
    property SettingsOperationTask vpnTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["vpn"]; active: root.page === "network" }
    property SettingsOperationTask sharingTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["sharing"]; active: root.page === "network" }
    property SettingsOperationTask hibernateTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["hibernate"]; active: root.page === "power" }
    property SettingsOperationTask assistiveTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["assistive"]; active: root.page === "input" }
    property SettingsOperationTask installedTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["installed"]; active: root.page === "apps" }
    property SettingsOperationTask permissionsTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["permissions"]; active: root.page === "apps" }
    property SettingsOperationTask disk_usageTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["disk-usage"]; active: root.page === "storage" }
    property SettingsOperationTask drivesTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["drives"]; active: root.page === "storage" }
    property SettingsOperationTask disk_healthTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["disk-health"]; active: root.page === "storage" }
    property SettingsOperationTask backupTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["backup"]; active: root.page === "storage" }
    property SettingsOperationTask restoreTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["restore"]; active: root.page === "storage" }
    property SettingsOperationTask snapshotsTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["snapshots"]; active: root.page === "storage" }
    property SettingsOperationTask updatesTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["updates"]; active: root.page === "system" }
    property SettingsOperationTask firmwareTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["firmware"]; active: root.page === "system" }
    property SettingsOperationTask accountsTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["accounts"]; active: root.page === "system" }
    property SettingsOperationTask datetimeTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["datetime"]; active: root.page === "system" }
    property SettingsOperationTask printersTask: SettingsOperationTask { script: "operations-settings.py"; arguments: ["printers"]; active: root.page === "system" }
    function provider(id) { return ({"vpn": vpnTask, "sharing": sharingTask, "hibernate": hibernateTask, "assistive": assistiveTask, "installed": installedTask, "permissions": permissionsTask, "disk-usage": disk_usageTask, "drives": drivesTask, "disk-health": disk_healthTask, "backup": backupTask, "restore": restoreTask, "snapshots": snapshotsTask, "updates": updatesTask, "firmware": firmwareTask, "accounts": accountsTask, "datetime": datetimeTask, "printers": printersTask})[id] || null }
}
