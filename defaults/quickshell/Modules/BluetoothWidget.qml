import QtQuick
import Quickshell.Bluetooth
import "../Components"

WidgetFrame {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var connectedDevices: {
        const values = Bluetooth.devices ? Bluetooth.devices.values : []
        const connected = []
        for (let index = 0; index < values.length; index++) {
            if (values[index] && values[index].connected)
                connected.push(values[index])
        }
        return connected
    }
    readonly property int connectionCount: connectedDevices.length
    readonly property bool enabled: adapter && adapter.enabled
    readonly property string deviceNames: {
        const names = []
        for (let index = 0; index < connectedDevices.length; index++)
            names.push(String(connectedDevices[index].name || connectedDevices[index].deviceName || "Device"))
        return names.join("\n")
    }

    visible: adapter !== null
    icon: !enabled ? "󰂲" : (connectionCount > 0 ? "󰂱" : "󰂯")
    label: !enabled ? "Off" : (connectionCount > 0 ? String(connectionCount) : "")
    tooltip: !enabled
        ? "Bluetooth disabled\nRight-click to enable"
        : (connectionCount > 0 ? deviceNames : "Bluetooth enabled · No connected devices")
    active: connectionCount > 0

    onPressed: button => {
        if (button === Qt.LeftButton)
            bar.run(["blueman-manager"])
        else if (button === Qt.RightButton && adapter)
            adapter.enabled = !adapter.enabled
    }
}
