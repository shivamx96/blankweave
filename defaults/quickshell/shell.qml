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
    property OsdService osd: OsdService {
        audio: root.audio
        focusedScreenName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : (Quickshell.screens[0]?.name || "")
        blocked: root.power.lowBattery.warningLevel > 0 || root.osd.panels.some(p => p.kind === "dictation")
    }
    property BrightnessRouter brightness: BrightnessRouter {
        osd: root.osd
        screens: Quickshell.screens
        focusedScreenName: root.osd.focusedScreenName
    }
    Variants {
        model: Quickshell.screens
        delegate: OsdToast { modelData: modelData; theme: root.theme; feedback: root.osd }
    }
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

    function openSettings(target) {
        root.closeLauncher()
        settingsWindow.openSettings(target || "")
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
            osd: root.osd
            suppressed: root.power.lowBattery.warningLevel > 0
        }
    }

    Variants {
        model: Quickshell.screens
        delegate: LowBatteryToast {
            modelData: modelData
            theme: root.theme
            power: root.power
        }
    }

    ApplicationLauncher {
        theme: root.theme
        usage: root.launcherUsage
        session: launcherSession
        onSettingRequested: target => root.openSettings(target)
        onDismissed: root.closeLauncher()
        onModeRequested: next => launcherSession.mode = next
    }

    IpcHandler {
        target: "blankweave"

        function volume(action: string): void { root.osd.volume(action) }
        function micMute(): void { root.osd.micMute() }
        function brightness(action: string): void { root.brightness.adjust(action) }

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

        // IpcHandler requires exact arity; preserve the legacy zero-argument method.
        function settingsTarget(target: string): void { root.openSettings(target) }

        function settings() {
            root.openSettings()
        }
    }
}
