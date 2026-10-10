import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "Bar"
import "Launcher"
import "Modules"
import "Services"
import "Settings"

ShellRoot {
    id: root

    property Theme theme: Theme { }
    property ShellPreferences preferences: ShellPreferences { }
    property Voxtype voxtype: Voxtype { }
    property AudioService audio: AudioService { }
    property WirelessControls wireless: WirelessControls { wifi: root.wifi; bluetooth: root.bluetooth; connections: root.connections }
    property NetworkConnections connections: NetworkConnections { }
    property NetworkWifi wifi: NetworkWifi { }
    property BluetoothService bluetooth: BluetoothService { }
    property AgentUsage agentUsage: AgentUsage { }
    property bool launcherOpen: false
    property string launcherMode: "applications"

    function openSettings() {
        root.closeLauncher()
        settingsWindow.openSettings()
    }

    SettingsWindow {
        id: settingsWindow
        theme: root.theme
        preferences: root.preferences
        sound: root.audio
        voice: root.voxtype
        wireless: root.wireless
        connections: root.connections
        wifi: root.wifi
        bluetooth: root.bluetooth
    }

    // The mode lives here rather than in the surface because Variants gives
    // every screen its own launcher; a keybinding for the other view should
    // switch the open one, not close it.
    function toggleLauncher(mode) {
        const next = mode || "applications"
        if (root.launcherOpen && root.launcherMode === next) {
            root.launcherOpen = false
            return
        }
        root.launcherMode = next
        root.launcherOpen = true
    }

    function closeLauncher() {
        root.launcherOpen = false
    }

    Variants {
        model: Quickshell.screens

        delegate: Bar {
            theme: root.theme
            shell: root
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: VoxtypeTranscriptToast {
            modelData: modelData
            theme: root.theme
            voice: root.voxtype
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: ApplicationLauncher {
            theme: root.theme
            mode: root.launcherMode
            open: root.launcherOpen
                && (!Hyprland.focusedMonitor
                    || modelData.name === Hyprland.focusedMonitor.name)
            onDismissed: root.closeLauncher()
            onModeRequested: next => root.launcherMode = next
        }
    }

    IpcHandler {
        target: "blankweave"

        function reload() {
            Quickshell.reload(true)
        }

        function launcher() {
            root.toggleLauncher("applications")
        }

        function clipboard() {
            root.toggleLauncher("clipboard")
        }

        function settings() {
            root.openSettings()
        }
    }
}
