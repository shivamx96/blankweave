import QtQuick
import Quickshell
import "Launcher"

ShellRoot {
    id: test
    property int step: 0
    property var displayA: ({name: "A"})
    property var displayB: ({name: "B"})
    property int refreshes: 0
    LauncherSession {
        id: session
        onRefreshRequested: test.refreshes++
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
