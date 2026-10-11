import QtQuick
import Quickshell.Hyprland
import Quickshell.Io

Item {
    id: root

    property var hyprland: Hyprland
    property var queryCommand: ["hyprctl", "-j", "activewindow"]
    property string focusedAddress: ""
    property int revision: 0
    property int queryRevision: -1
    property string error: ""
    readonly property bool initializing: query.running
    readonly property var activeWindow: {
        if (!focusedAddress)
            return null
        const current = hyprland.activeToplevel
        if (current && normalizeAddress(current.address) === focusedAddress)
            return current
        return hyprland.toplevels.values.find(window => normalizeAddress(window.address) === focusedAddress) || null
    }

    visible: false

    function normalizeAddress(value) {
        if (typeof value !== "string" || !/^(?:0x)?[0-9a-f]{1,16}$/i.test(value))
            return ""
        return value.toLowerCase().replace(/^0x/, "").replace(/^0+(?=.)/, "")
    }

    Connections {
        target: root.hyprland

        function onRawEvent(event) {
            if (event.name !== "activewindowv2")
                return
            const address = root.normalizeAddress(event.data)
            const current = root.hyprland.activeToplevel
            if (event.data !== "" && (!address || !current
                || address !== root.normalizeAddress(current.address)))
                return
            root.revision++
            root.focusedAddress = address
            root.error = ""
        }
    }

    Process {
        id: query
        command: root.queryCommand
        stdout: StdioCollector { id: output }
        onExited: (exitCode, exitStatus) => {
            if (root.queryRevision !== root.revision)
                return
            try {
                if (exitCode !== 0 || exitStatus !== 0)
                    throw new Error("Could not read the active window")
                const snapshot = JSON.parse(output.text)
                if (!snapshot || typeof snapshot !== "object" || Array.isArray(snapshot))
                    throw new Error("Invalid active window response")
                const address = root.normalizeAddress(snapshot.address)
                if (Object.keys(snapshot).length > 0 && !address)
                    throw new Error("Invalid active window address")
                root.focusedAddress = address
            } catch (error) {
                root.error = String(error)
            }
        }
    }

    Component.onCompleted: {
        queryRevision = revision
        query.running = true
    }
}
