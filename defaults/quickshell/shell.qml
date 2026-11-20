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

    // Policy persists independently of the Settings window. A fresh process also
    // picks up clock/timezone changes and retries after Dunst restarts.
    Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: { if (!notificationPolicy.running) notificationPolicy.running = true } }
    Process { id: notificationPolicy; command: ["python3", Quickshell.env("HOME") + "/.local/share/blankweave/shell/notification-settings.py", "tick"] }
    property Theme theme: Theme { }
    property LauncherUsage launcherUsage: LauncherUsage { }
    property ShellPreferences preferences: ShellPreferences { }
    property Voxtype voxtype: Voxtype { }
    property PowerService power: PowerService { }
    property AudioService audio: AudioService { }
    property ActiveWindow activeWindow: ActiveWindow { }
    property WirelessControls wireless: WirelessControls { wifi: root.wifi; bluetooth: root.bluetooth; connections: root.connections }
    property NetworkConnections connections: NetworkConnections { }
    property NetworkWifi wifi: NetworkWifi { }
    property BluetoothService bluetooth: BluetoothService { }
    property PollerService pollers: PollerService { }
    property AgentUsage agentUsage: AgentUsage { }
    LauncherSession {
        id: launcherSession
        screens: Quickshell.screens
        focusedScreenName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    }

    // Reuse the launcher's focused-output selection and hotplug fallback policy.
    property PanelSession panels: PanelSession {
        onOpenChanged: if (open) root.closeLauncher()
        screens: Quickshell.screens
        focusedScreenName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    }

    readonly property var powerMenu: panels

    function togglePanel(id) {
        root.panels.request(id)
        if (root.panels.open) root.closeLauncher()
    }

    function togglePower() {
        root.closeLauncher()
        root.togglePanel("power")
    }

    function openSettings() {
        settingsWindow.openSettings()
    }

    SettingsWindow {
        id: settingsWindow
        theme: root.theme
        preferences: root.preferences
        power: root.power
        sound: root.audio
        voice: root.voxtype
        wireless: root.wireless
        connections: root.connections
        wifi: root.wifi
        bluetooth: root.bluetooth
    }

    function toggleLauncher(mode) {
        root.panels.dismiss()
        launcherSession.toggle(mode || "applications")
    }

    function closeLauncher() {
        launcherSession.dismiss()
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

    ApplicationLauncher {
        theme: root.theme
        usage: root.launcherUsage
        session: launcherSession
        onDismissed: root.closeLauncher()
        onModeRequested: next => launcherSession.mode = next
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

        function panel(id: string): void { root.togglePanel(id) }

        function power() {
            root.togglePower()
        }

        function settings() {
            root.openSettings()
        }
    }
}
