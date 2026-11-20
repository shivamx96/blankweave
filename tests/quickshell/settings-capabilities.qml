import QtQuick
import Quickshell
import "Services"
Scope {
    SettingsCapabilities { id: valid; path: Quickshell.env("CAPABILITIES_TEST_ROOT") + "/valid.json" }
    SettingsCapabilities { id: broken; path: Quickshell.env("CAPABILITIES_TEST_ROOT") + "/broken.json" }
    SettingsCapabilities { id: missing; path: Quickshell.env("CAPABILITIES_TEST_ROOT") + "/missing.json" }
    Timer {
        interval: 300; running: true
        onTriggered: {
            if (!valid.capabilities || valid.capabilities.join(",") !== "battery,wifi" || broken.capabilities !== null || missing.capabilities !== null) throw new Error("Capability read or fail-open failed")
            console.log("SETTINGS_CAPABILITIES_PASSED")
            Qt.quit()
        }
    }
}
