import QtQuick
import Quickshell
import "Launcher"
import "Launcher/Launch.js" as Launch

ShellRoot {
    id: test
    property int step: 0
    property real armedAt: 0
    property var displayA: ({name: "A"})
    property var displayB: ({name: "B"})
    property int refreshes: 0
    LauncherSession {
        id: session
        onRefreshRequested: test.refreshes++
    }
    Theme { id: theme }
    LauncherSession { id: searchSession }
    property var commands: []
    property string destination: ""
    ApplicationLauncher {
        id: launcher
        theme: theme
        session: searchSession
        executeCommand: argv => test.commands.push(argv)
        onSettingRequested: target => test.destination = target
        onDismissed: searchSession.dismiss()
    }
    function checkClipboard() {
        searchSession.mode = "clipboard"
        searchSession.searchText = ""
        launcher.completeClipboardLoad("12\tfirst\n13\tsecond\n14\tthird")
        searchSession.selectedIndex = 1
        let mutation = null
        launcher.runClipboardMutation = argv => mutation = argv
        launcher.deleteClipboard()
        check(mutation[4] === "13" && mutation[2] === 'cliphist delete "$1"'
            && !mutation[2].includes("13"), "Delete id is an argument")
        check(launcher.clipboardEntries.length === 3, "No optimistic deletion")
        launcher.completeClipboardLoad("12\tfirst\n14\tthird")
        check(searchSession.selectedIndex === 1 && launcher.results[1].clipboardId === "14", "Select next row")
        launcher.deleteClipboard()
        launcher.completeClipboardLoad("12\tfirst")
        check(searchSession.selectedIndex === 0, "Last deletion selects previous row")
        check(launcher.canDeleteClipboard(3, 3, 3, 3), "Delete at query end")
        check(!launcher.canDeleteClipboard(2, 3, 2, 2), "Delete in query edits text")
        check(!launcher.canDeleteClipboard(3, 3, 0, 3), "Selection edits text")
        launcher.clearClipboard()
        check(launcher.armedAction === "clipboard-clear", "Clear arms")
        launcher.clearClipboard()
        check(JSON.stringify(mutation) === '["cliphist","wipe"]' && launcher.armedAction === "", "Clear confirms")
        launcher.clearClipboard()
        searchSession.searchText = "x"
        check(launcher.armedAction === "", "Clear query disarm")
        searchSession.searchText = ""
        launcher.clearClipboard()
        launcher.closeLauncher()
        check(launcher.armedAction === "", "Escape/close disarms")
        searchSession.mode = "applications"
        check(launcher.armedAction === "", "View disarms")
        searchSession.mode = "clipboard"
        launcher.refresh()
        check(launcher.clipboardEntries.length === 1 && !launcher.showEmpty, "Reload retains previous list")
        searchSession.mode = "applications"
    }
    function checkSearch() {
        launcher.lastPointer = Qt.point(-1, -1)
        check(!launcher.pointerMoved(100, 100), "Surface under stationary pointer only establishes baseline")
        searchSession.selectedIndex = 1
        check(!launcher.pointerMoved(100, 100), "Stationary pointer preserves keyboard choice")
        check(searchSession.selectedIndex === 1, "Keyboard choice unchanged")
        launcher.pointerRow(100, 100, 0)
        check(searchSession.selectedIndex === 1, "Rerank beneath stationary pointer preserves selection")
        launcher.pointerRow(101, 100, 0)
        check(searchSession.selectedIndex === 0, "Pointer movement selects row")
        for (const mode of ["applications", "clipboard"]) {
            searchSession.mode = mode
            searchSession.selectedIndex = 1
            launcher.pointerRow(101, 100, 0)
            check(searchSession.selectedIndex === 1, "Stationary pointer in " + mode)
            launcher.pointerRow(102, 100, 0)
            check(searchSession.selectedIndex === 0, "Moving pointer in " + mode)
            launcher.lastPointer = Qt.point(101, 100)
        }
        searchSession.mode = "applications"

        check(launcher.rankApplications("").every(e => !e.kind), "Empty query contains only apps")
        let rows = launcher.rankApplications("keyboard shortcuts")
        let setting = rows.find(e => e.kind === "setting" && e.id === "shortcuts")
        check(Boolean(setting) && setting.genericName === "Input & Accessibility", "Settings row and page subtitle")
        launcher.activate(setting)
        check(test.destination === "input/shortcuts", "Settings activation deep links")
        rows = launcher.rankApplications("Desktop theme")
        check(rows[0].name === "Desktop theme" && !rows[0].kind, "Application wins equal Settings match")
        check(rows.some(e => e.kind === "setting" && e.id === "theme"), "Matching Settings still appears")
        check(launcher.systemActions.length === 7, "Only seven system actions")
        for (const action of launcher.systemActions) {
            const found = launcher.rankApplications(action.name).find(e => e.kind === "system" && e.id === action.id)
            check(Boolean(found), "System action searchable: " + action.id)
            searchSession.open = true
            const before = test.commands.length
            launcher.activate(found)
            if (action.guarded) {
                check(test.commands.length === before && searchSession.open, "First Enter only arms")
                check(launcher.rowSubtitle(found).indexOf("Press Enter again") === 0, "Visible confirmation")
                launcher.activate(found)
            }
            check(test.commands.length === before + 1 && !searchSession.open, "Confirmed action executes once and closes")
            check(JSON.stringify(test.commands[test.commands.length - 1]) === JSON.stringify(action.command), "Shared command")
        }
        const restart = Object.assign({kind: "system"}, launcher.systemActions.find(e => e.id === "restart"))
        searchSession.open = true
        launcher.activate(restart)
        searchSession.searchText = "changed"
        check(launcher.armedAction === "", "Query change disarms")
        launcher.activate(restart)
        searchSession.selectedIndex++
        check(launcher.armedAction === "", "Selection change disarms")
        launcher.activate(restart)
        searchSession.dismiss()
        check(launcher.armedAction === "", "Close disarms")
        launcher.automaticSignIn = false
        check(launcher.systemActions.find(e => e.id === "logout").name === "Log out", "Password sign-in label")
    }
    function check(condition, message) {
        if (!condition) throw new Error(message)
    }
    Timer {
        interval: 50; running: true; repeat: true
        onTriggered: {
            try {
                switch (test.step) {
                case 0:
                    const entry = DesktopEntries.applications.values.find(e => e.name === "Blankweave fake terminal")
                    if (!entry) return
                    check(entry.runInTerminal, "DesktopEntry exposes terminal flag")
                    check(entry.command.length === 2 && entry.command[1] === "two words", "Parsed argv drops file field codes")
                    let captured = null
                    Launch.activate(entry, argv => captured = argv)
                    check(JSON.stringify(captured) === JSON.stringify(["ghostty", "--working-directory=/tmp", "-e", "never-launch-this", "two words"]), "Detached launch uses parsed arguments and working directory")
                    test.checkClipboard()
                    test.checkSearch()
                    session.screens = [test.displayA, test.displayB]
                    session.focusedScreenName = "A"
                    session.toggle("applications")
                    break
                case 1:
                    check(session.targetName === "A", "Invocation should use focused output")
                    session.searchText = "needle"
                    session.selectedIndex = 3
                    session.focusedScreenName = "B"
                    break
                case 2:
                    check(session.targetName === "A", "Pointer focus moved the open launcher")
                    check(session.searchText === "needle" && session.selectedIndex === 3, "Focus change lost query")
                    session.screens = [test.displayB]
                    break
                case 3:
                    check(session.targetName === "B", "Disconnected output did not fall back")
                    check(session.searchText === "needle" && session.selectedIndex === 3, "Fallback lost query")
                    session.screens = [test.displayA, test.displayB]
                    break
                case 4:
                    check(session.targetName === "B", "Reconnect stole the launcher back")
                    session.screens = []
                    break
                case 5:
                    check(session.open && session.targetScreen === null, "Zero outputs must hide without ending invocation")
                    check(session.searchText === "needle", "Zero outputs lost query")
                    session.screens = [test.displayA, test.displayB]
                    break
                case 6:
                    check(session.targetName === "B" && session.searchText === "needle", "Restore did not preserve invocation")
                    session.toggle("applications")
                    check(!session.open, "Same shortcut should dismiss")
                    break
                case 7:
                    session.focusedScreenName = "A"
                    session.toggle("clipboard")
                    break
                case 8:
                    check(session.targetName === "A", "New invocation did not choose new output")
                    check(test.refreshes === 2, "Only new invocations should refresh results")
                    session.searchText = "saved"
                    session.selectedIndex = 1
                    session.screens = [test.displayB]
                    break
                case 9:
                    check(session.targetName === "B" && session.searchText === "saved" && session.selectedIndex === 1,
                          "Clipboard fallback lost selection or query")
                    check(test.refreshes === 2, "Fallback must not refresh clipboard results")
                    session.toggle("applications")
                    break
                case 10:
                    check(session.open && session.targetName === "B", "Switching mode should stay on the same output")
                    check(session.searchText === "" && session.selectedIndex === 0, "Mode switch should reset its search")
                    session.dismiss()
                    session.screens = [test.displayA, test.displayB]
                    session.focusedScreenName = "missing"
                    session.toggle("applications")
                    break
                case 11:
                    check(session.targetName === "A", "Missing focused monitor should use first connected output")
                    check(test.refreshes === 4, "Mode switch and new invocation should each refresh once")
                    searchSession.mode = "clipboard"
                    launcher.completeClipboardLoad("1\tentry")
                    launcher.clearClipboard()
                    test.armedAt = Date.now()
                    check(launcher.armedAction === "clipboard-clear", "Timeout test arms")
                    break
                case 12:
                    if (Date.now() - test.armedAt < 5200) return
                    check(launcher.armedAction === "", "Clear expires after five seconds")
                    console.log("LAUNCHER_SESSION_PASSED")
                    Qt.quit()
                }
                test.step++
            } catch (error) {
                console.error(String(error))
                Qt.quit()
            }
        }
    }
}
