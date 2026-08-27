import QtQuick
import Quickshell
import Quickshell.Io
import "Bar"

ShellRoot {
    id: root

    property Theme theme: Theme { }

    Variants {
        model: Quickshell.screens

        delegate: Bar {
            theme: root.theme
        }
    }

    IpcHandler {
        target: "hyprarch"

        function reload() {
            Quickshell.reload(true)
        }
    }
}
