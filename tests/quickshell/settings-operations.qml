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
                vpn.draft.begin({key:"fixture",label:"Fixture",confirm:"",fields:[{key:"folder",label:"Folder",value:"reject",secret:false,options:[]}]})
                vpn.draft.submit()
                operations.page = "apps"
                root.step = 1
            } else if (root.step === 1 && !vpn.busy && operations.provider("installed").ready && operations.provider("permissions").ready) {
                if (!vpn.draft.error.includes("unavailable") || vpn.draft.values.folder !== "reject" || vpn.draft.pending) throw new Error("Failed request lost its draft")
                vpn.draft.setValue("folder", "accepted")
                vpn.draft.submit()
                root.step = 2
            } else if (root.step === 2 && !vpn.busy && !vpn.draft.pending) {
                if (vpn.error || vpn.request !== "" || vpn.draft.editing !== null) throw new Error("Successful job did not clear its draft")
                if (vpn.active || operations.provider("sharing").active) throw new Error("Hidden network page is still active")
                console.log("SETTINGS_OPERATIONS_PASSED")
                Qt.callLater(() => Qt.quit())
                root.step = 3
            }
        }
    }
}
