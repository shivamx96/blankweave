import QtQuick
import Quickshell
import Quickshell.Io

// One read per Settings window; unavailable or malformed detection fails open.
QtObject {
    id: root
    property var capabilities: null
    property string path: Quickshell.env("HOME") + "/.local/share/blankweave/hardware-capabilities.json"
    property FileView source: FileView {
        path: root.path
        onLoaded: {
            try {
                const data = JSON.parse(text())
                root.capabilities = Array.isArray(data.capabilities) && data.capabilities.every(value => typeof value === "string") ? data.capabilities : null
            } catch (error) { root.capabilities = null }
        }
        onLoadFailed: root.capabilities = null
    }
}
