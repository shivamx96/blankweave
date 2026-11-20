import QtQuick
import Quickshell
import "Modules"
import "Launcher"
import "Services"
import "Components/PanelNavigation.js" as Navigation
ShellRoot {
    id: root
    property int step: 0
    property Theme theme: Theme { reducedMotion: true }
    property PanelSession menu: PanelSession {
        screens: Quickshell.screens
        focusedScreenName: Quickshell.screens.length ? Quickshell.screens[0].name : ""
    }
    FloatingWindow {
        visible: true
        id: bar
        property bool atBottom: false
        property bool held: false
        property var commands: []
        property var shell: QtObject { property var panels: root.menu }
        function setVisibilityHold(owner, open) { held = open }
        function hideTooltip(owner) {}
        function showTooltip(owner, text) {}
        function run(command) { commands.push(command.join(" ")) }
        implicitWidth: 1000
        implicitHeight: root.theme.barHeight
        PowerWidget { id: widget; bar: bar; theme: root.theme }
    }
    function check(value, message) { if (!value) throw new Error("Power menu step " + step + ": " + message) }
    function key(code) {
        const popup = root.menu.panels[0]
        if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space].includes(code)) {
            const item = Navigation.controls(popup.navigationScope).find(i => i.activeFocus)
            if (item) item.clicked(null)
        } else widget.handleKey({key: code, modifiers: 0, accepted: false})
    }
    Timer {
        interval: 150; repeat: true; running: true
        onTriggered: {
            try {
                switch (root.step++) {
                case 0:
                    root.menu.request("power"); break
                case 1:
                    root.check(widget.active && bar.held, "IPC state opens and holds reveal")
                    root.key(Qt.Key_Right); root.key(Qt.Key_Return)
                    root.check(widget.pendingAction === "logout" && bar.commands.length === 0, "keyboard arms logout")
                    root.key(Qt.Key_Escape)
                    root.check(!root.menu.open && !bar.held && widget.pendingAction === "", "Escape clears confirmation and hold")
                    bar.atBottom = true; root.menu.request("power"); break
                case 2:
                    root.check(widget.active && bar.held, "bottom edge opens")
                    root.menu.request("power")
                    root.check(!widget.active && !bar.held, "second IPC closes")
                    root.menu.request("power"); break
                case 3:
                    root.key(Qt.Key_Tab); root.key(Qt.Key_Return); root.key(Qt.Key_Enter); break
                case 4:
                    root.check(bar.commands.length === 1 && bar.commands[0] === "uwsm stop", "second activation dispatches only to stub")
                    root.check(!widget.active && widget.pendingAction === "", "execution closes and resets")
                    root.menu.request("power"); break
                case 5:
                    root.key(Qt.Key_Return); break
                case 6:
                    root.check(bar.commands.length === 2 && bar.commands[1] === "sh -c ~/.local/share/blankweave/shell/lock.sh", "lock is immediate")
                    root.menu.request("power"); break
                case 7:
                    root.key(Qt.Key_Tab); root.key(Qt.Key_Down); root.key(Qt.Key_Return); break
                case 8:
                    root.check(bar.commands.length === 3 && bar.commands[2] === "systemctl suspend", "suspend is immediate")
                    console.log("POWER_MENU_PASSED"); Qt.quit()
                }
            } catch (error) { console.error(error); Qt.quit() }
        }
    }
}
