import QtQuick

QtObject {
    id: root
    property string page: ""
    property SettingsTask vpnTask: SettingsTask { script: "operations-settings.py"; arguments: ["vpn"]; active: root.page === "network" }
    property SettingsTask sharingTask: SettingsTask { script: "operations-settings.py"; arguments: ["sharing"]; active: root.page === "network" }
    property SettingsTask hibernateTask: SettingsTask { script: "operations-settings.py"; arguments: ["hibernate"]; active: root.page === "power" }
    property SettingsTask assistiveTask: SettingsTask { script: "operations-settings.py"; arguments: ["assistive"]; active: root.page === "input" }
    property SettingsTask installedTask: SettingsTask { script: "operations-settings.py"; arguments: ["installed"]; active: root.page === "apps" }
    property SettingsTask permissionsTask: SettingsTask { script: "operations-settings.py"; arguments: ["permissions"]; active: root.page === "apps" }
    property SettingsTask disk_usageTask: SettingsTask { script: "operations-settings.py"; arguments: ["disk-usage"]; active: root.page === "storage" }
    property SettingsTask drivesTask: SettingsTask { script: "operations-settings.py"; arguments: ["drives"]; active: root.page === "storage" }
    property SettingsTask disk_healthTask: SettingsTask { script: "operations-settings.py"; arguments: ["disk-health"]; active: root.page === "storage" }
    property SettingsTask backupTask: SettingsTask { script: "operations-settings.py"; arguments: ["backup"]; active: root.page === "storage" }
    property SettingsTask restoreTask: SettingsTask { script: "operations-settings.py"; arguments: ["restore"]; active: root.page === "storage" }
    property SettingsTask snapshotsTask: SettingsTask { script: "operations-settings.py"; arguments: ["snapshots"]; active: root.page === "storage" }
    property SettingsTask updatesTask: SettingsTask { script: "operations-settings.py"; arguments: ["updates"]; active: root.page === "system" }
    property SettingsTask firmwareTask: SettingsTask { script: "operations-settings.py"; arguments: ["firmware"]; active: root.page === "system" }
    property SettingsTask accountsTask: SettingsTask { script: "operations-settings.py"; arguments: ["accounts"]; active: root.page === "system" }
    property SettingsTask datetimeTask: SettingsTask { script: "operations-settings.py"; arguments: ["datetime"]; active: root.page === "system" }
    property SettingsTask printersTask: SettingsTask { script: "operations-settings.py"; arguments: ["printers"]; active: root.page === "system" }
    function provider(id) { return ({"vpn": vpnTask, "sharing": sharingTask, "hibernate": hibernateTask, "assistive": assistiveTask, "installed": installedTask, "permissions": permissionsTask, "disk-usage": disk_usageTask, "drives": drivesTask, "disk-health": disk_healthTask, "backup": backupTask, "restore": restoreTask, "snapshots": snapshotsTask, "updates": updatesTask, "firmware": firmwareTask, "accounts": accountsTask, "datetime": datetimeTask, "printers": printersTask})[id] || null }
}
