import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "Bar"
import "Launcher"
import "Services"

ShellRoot {
    id: root

    property Theme theme: Theme { }
    property ShellPreferences preferences: ShellPreferences { }
    property bool launcherOpen: false

    function toggleLauncher() {
        root.launcherOpen = !root.launcherOpen
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

        delegate: ApplicationLauncher {
            theme: root.theme
            open: root.launcherOpen
                && (!Hyprland.focusedMonitor
                    || modelData.name === Hyprland.focusedMonitor.name)
            onDismissed: root.closeLauncher()
        }
    }

    IpcHandler {
        target: "hyprarch"

        function reload() {
            Quickshell.reload(true)
        }

        function launcher() {
            root.toggleLauncher()
        }
    }
}
