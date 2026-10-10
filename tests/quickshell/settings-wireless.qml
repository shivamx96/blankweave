import QtQuick
import QtQuick.Layouts
import Quickshell
import "Services"
import "Settings"

ShellRoot {
    id: test
    Theme { id: theme }
    QtObject { id: wifi; property bool localBusy: false; property bool externalBusy: false }
    QtObject { id: bluetooth; property bool localBusy: false; property bool externalBusy: false }
    QtObject { id: connections; property bool localBusy: false; property bool externalBusy: false; function refresh() {} }
    WirelessControls {
        id: wireless
        helper: Qt.resolvedUrl("wireless.py").toString().replace("file://", "")
        wifi: wifi; bluetooth: bluetooth; connections: connections
    }
    FloatingWindow { visible: true; implicitWidth: 700; implicitHeight: 1100
        ColumnLayout { width: 640
            SettingsWireless { id: airplane; theme: theme; backend: wireless; Layout.fillWidth: true }
            SettingsWireless { id: hotspot; theme: theme; backend: wireless; hotspot: true; Layout.fillWidth: true }
        }
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
            if (wireless.busy) return
            try {
                switch (test.step) {
                case 0:
                    wireless.active = true
                    break
                case 1:
                    test.verify(wireless.airplane !== null && wireless.devices.length === 1)
                    test.verify(hotspot.canStart)
                    bluetooth.localBusy = true
                    test.verify(wireless.otherBusy)
                    wireless.setAirplane(true)
                    test.verify(!wireless.applying)
                    bluetooth.localBusy = false
                    wireless.setAirplane(true)
                    test.verify(wireless.applying && wifi.externalBusy && bluetooth.externalBusy && connections.externalBusy)
                    break
                case 2:
                    test.verify(wireless.radiosBlocked && wireless.airplaneRequested)
                    test.verify(!hotspot.canStart)
                    test.verify(!wifi.externalBusy && !bluetooth.externalBusy)
                    wireless.setAirplane(false)
                    break
                case 3:
                    test.verify(!wireless.radiosBlocked)
                    find(hotspot, "hotspotName").text = "Test sharing"
                    find(hotspot, "hotspotPassword").text = "test-secret"
                    hotspot.start()
                    test.verify(hotspot.confirmation !== null && !wireless.applying)
                    hotspot.start()
                    test.verify(find(hotspot, "hotspotPassword").text === "")
                    test.verify(hotspot.confirmation === null)
                    break
                case 4:
                    test.verify(wireless.devices[0].hotspot && wireless.devices[0].owned)
                    test.verify(find(hotspot, "hotspotStop").visible)
                    test.verify(!find(hotspot, "hotspotStart").visible)
                    wireless.stop(wireless.devices[0])
                    break
                case 5:
                    test.verify(!wireless.devices[0].hotspot)
                    find(hotspot, "hotspotName").text = "Fail"
                    find(hotspot, "hotspotPassword").text = "test-secret"
                    hotspot.start()
                    break
                case 6:
                    test.verify(wireless.error.includes("failed"))
                    test.verify(find(hotspot, "hotspotPassword").text === "")
                    test.saved = wireless.network
                    wireless.network = Object.assign({}, test.saved, {devices: [Object.assign({}, test.saved.devices[0], {uuid:"old", activePath:"/old", name:"Old Wi-Fi", connected:true, state:100})]})
                    find(hotspot, "hotspotName").text = "Test sharing"
                    find(hotspot, "hotspotPassword").text = "test-secret"
                    hotspot.start()
                    test.verify(hotspot.confirmation !== null)
                    wireless.network = test.saved
                    test.verify(hotspot.confirmation === null)
                    test.verify(find(hotspot, "hotspotPassword").text === "")
                    find(hotspot, "hotspotPassword").text = "test-secret"
                    wireless.active = false
                    test.verify(find(hotspot, "hotspotPassword").text === "")
                    wireless.network = Object.assign({}, test.saved, {sharingAvailable:false})
                    test.verify(!hotspot.canStart)
                    wireless.network = Object.assign({}, test.saved, {devices:[]})
                    test.verify(hotspot.selected === null)
                    wireless.helper = "/missing-wireless-helper"
                    wireless.refresh()
                    break
                default:
                    test.verify(wireless.airplane === null && wireless.network === null && wireless.error !== "")
                    console.log("SETTINGS_WIRELESS_PASSED"); Qt.quit()
                }
                test.step++
            } catch (error) { console.error(String(error), error.stack); Qt.quit() }
        }
    }
}
