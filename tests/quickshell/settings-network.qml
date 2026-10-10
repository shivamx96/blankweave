import QtQuick
import Quickshell
import "Services"
import "Settings"

ShellRoot {
    id: test
    Theme { id: theme }
    NetworkConnections { id: network; helper: Qt.resolvedUrl("network.py").toString().replace("file://", "") }
    FloatingWindow { visible: true; implicitWidth: 700; implicitHeight: 900
        SettingsNetwork { id: controls; theme: theme; backend: network; width: 640 }
    }
    property int step: 0
    property var saved: null
    function verify(value) { if (!value) throw new Error("Assertion failed at step " + step) }
    function find(parent, name) {
        if (parent.objectName === name) return parent
        for (const child of parent.children || []) { const result = find(child, name); if (result) return result }
        return null
    }
    Timer {
        running: true; repeat: true; interval: 150
        onTriggered: {
            if (network.busy) return
            try {
                switch (test.step) {
                case 0:
                    network.settingsActive = true
                    network.setActive("bar", true)
                    network.settingsActive = false
                    test.verify(network.active)
                    network.setActive("bar", false)
                    test.verify(!network.active)
                    network.settingsActive = true
                    break
                case 1:
                    test.verify(network.ready && network.devices.length === 1)
                    test.verify(controls.selected !== null)
                    test.verify(find(controls, "ethernetConnect:" + network.devices[0].path).text === "Disconnect")
                    controls.beginEdit()
                    test.verify(controls.provider === "Automatic")
                    controls.provider = "Cloudflare"
                    controls.save()
                    test.verify(network.pending !== "")
                    test.verify(network.devices[0].provider === "Automatic")
                    break
                case 2:
                    test.verify(network.devices[0].provider === "Cloudflare")
                    test.verify(network.notice !== "")
                    controls.beginEdit()
                    controls.provider = "Custom"
                    controls.save()
                    break
                case 3:
                    test.verify(network.error.includes("valid IPv4"))
                    controls.beginEdit()
                    test.saved = network.devices[0]
                    network.devices = [Object.assign({}, test.saved, {uuid: "different", activePath: "/active/3"})]
                    test.verify(controls.stale)
                    test.verify(!find(controls, "dnsSave").enabled)
                    network.setDns(test.saved, "Google")
                    test.verify(!network.busy)
                    test.verify(network.error.includes("changed"))
                    network.settingsActive = false
                    test.verify(controls.editing === null)
                    network.devices = [test.saved]
                    const chooser = find(controls, "dnsConnection")
                    chooser.popup.open()
                    network.devices = [Object.assign({}, test.saved, {uuid: "new-profile", activePath: "/active/9"})]
                    controls.selectedPath = ""
                    chooser.activated(0)
                    test.verify(controls.selectedPath === "")
                    chooser.popup.close()
                    network.devices = [test.saved]
                    network.disconnectDevice(test.saved)
                    break
                case 4:
                    test.verify(!network.devices[0].connected)
                    test.verify(controls.connections.length === 0)
                    test.verify(find(controls, "ethernetConnect:" + network.devices[0].path).text === "Connect")
                    network.connectDevice(network.devices[0], "test-uuid")
                    break
                case 5:
                    test.verify(network.devices[0].connected)
                    test.saved = network.devices[0]
                    network.devices = [Object.assign({}, test.saved, {connected: false, carrier: false, activePath: "/"})]
                    test.verify(!find(controls, "ethernetConnect:" + test.saved.path).enabled)
                    network.devices = []
                    test.verify(controls.selected === null)
                    network.helper = "/missing-network-helper"
                    network.refresh()
                    break
                default:
                    test.verify(!network.ready && network.error !== "")
                    console.log("SETTINGS_NETWORK_PASSED"); Qt.quit()
                }
                test.step++
            } catch (error) { console.error(String(error), error.stack); Qt.quit() }
        }
    }
}
