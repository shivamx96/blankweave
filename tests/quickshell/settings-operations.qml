import QtQuick
import Quickshell
import "Services"
Scope {
    id: root
    property int step: 0
    SettingsOperationsService { id: operations }
    Component.onCompleted: {
        for (const domain of ["vpn", "sharing", "hibernate", "assistive", "installed", "permissions", "disk-usage", "drives", "disk-health", "backup", "restore", "snapshots", "updates", "firmware", "accounts", "datetime", "printers"])
            operations.provider(domain).helper = Quickshell.shellDir + "/fixture.py"
        operations.page = "network"
    }
    Timer {
        interval: 30; running: true; repeat: true
        onTriggered: {
            const vpn = operations.provider("vpn")
            if (root.step === 0 && vpn.writable && operations.provider("sharing").ready) {
                if (operations.provider("installed").ready) throw new Error("Inactive page was polled")
                vpn.apply({action: "fixture"})
                operations.page = "apps"
                root.step = 1
            } else if (root.step === 1 && !vpn.busy && operations.provider("installed").ready && operations.provider("permissions").ready) {
                if (vpn.error || vpn.request !== "") throw new Error("Request failed or credentials retained")
                if (vpn.active || operations.provider("sharing").active) throw new Error("Hidden network page is still active")
                console.log("SETTINGS_OPERATIONS_PASSED")
                Qt.callLater(() => Qt.quit())
                root.step = 2
            }
        }
    }
}
