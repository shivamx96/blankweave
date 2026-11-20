import QtQuick
import QtTest
import "../../defaults/quickshell/Launcher/Launch.js" as Launch
import "../../defaults/quickshell/Components/TooltipHints.js" as Hints

TestCase {
    name: "LaunchAndTooltipHints"
    function test_launch() {
        let launched = null
        let executions = 0
        const entry = {runInTerminal: false, execute: () => executions++}
        Launch.activate(entry, argv => launched = argv)
        compare(executions, 1)
        compare(launched, null)
        entry.runInTerminal = true
        // Fake parsed argv: spaces and shell metacharacters must remain literal.
        entry.command = ["fake-monitor", "a b", "$(false)", "%"]
        entry.workingDirectory = "/tmp/a b"
        Launch.activate(entry, argv => launched = argv)
        compare(launched, ["ghostty", "--working-directory=/tmp/a b", "-e", "fake-monitor", "a b", "$(false)", "%"])
        compare(executions, 1)
        entry.workingDirectory = ""
        Launch.activate(entry, argv => launched = argv)
        compare(launched[1], "-e")
    }
    function test_hints() {
        compare(Hints.text("Status", "refresh", ""), "Status\nRight-click: refresh")
        compare(Hints.text("Status", "", "adjust"), "Status\nScroll: adjust")
        compare(Hints.text("Status", "mute", "adjust"), "Status\nRight-click: mute · Scroll: adjust")
        compare(Hints.text("Status", "", ""), "Status")
    }
}
