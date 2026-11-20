import QtQuick
import Quickshell
import "Services"
import "Components"

ShellRoot {
    id: test
    property string helper: Quickshell.env("POLLER_TEST_DIR") + "/fake.sh"
    property int stage: 0
    property int ticks: 0
    property PollerService pollers: PollerService { }
    QtObject { id: barOne; property var shell: test }
    QtObject { id: barTwo; property var shell: test }
    SharedPoller { id: first; service: barOne.shell.pollers; key: "cpu"; command: test.helper + " count"; interval: 0 }
    SharedPoller { id: second; service: barTwo.shell.pollers; key: "cpu"; command: test.helper + " count"; interval: 0 }
    ScriptPoller { id: poll; command: test.helper + " good"; interval: 0; timeout: 150 }
    QtObject { id: theme; property color textMuted: "#888888"; property color text: "white"; property color critical: "red"; property color accentBright: "cyan"; property int widgetPadding: 0; property int barIconSize: 16; property int widgetHeight: 20; property int widgetContentGap: 2; property string fontFamily: "sans"; property string iconFontFamily: "sans"; property int textSize: 12; property int motionDuration: 0; property int motionEasing: Easing.Linear }
    Item {
        id: frameBar
        property bool atBottom: false
        function hideTooltip(owner) {}
        function showTooltip(owner, text) {}
        WidgetFrame { id: frame; bar: frameBar; theme: theme; label: poll.ready ? JSON.parse(poll.output).text : "—"; dataSources: [poll]; attention: true }
    }
    function check(value, message) { if (!value) { console.error(message); Qt.exit(1) } }
    function run(mode) { poll.command = helper + " " + mode; poll.refresh() }
    Timer {
        interval: 30; running: true; repeat: true
        onTriggered: {
            test.ticks++
            if (test.ticks > 250) { console.error("Poller test timed out at stage", test.stage); Qt.exit(1) }
            if (test.stage === 0 && poll.ready && first.ready && second.ready) {
                check(first.source === second.source, "Bars must share a collector")
                check(first.output === '{"text":"1"}', "Only one initial invocation")
                second.interval = 5000
                check(first.source.interval === 5000, "Second view requests polling")
                first.interval = 1000
                check(first.source.interval === 1000, "Fastest request wins")
                first.interval = 0
                check(first.source.interval === 5000, "Releasing fast request retains second")
                second.interval = 0
                check(!poll.stale && poll.error === "", "Good result is fresh")
                run("hang"); test.stage = 1
            } else if (test.stage === 1 && poll.stale && !poll.running) {
                check(poll.error === "Collection timed out", "Timeout must be identified")
                check(frame.label === "42" && frame.foreground === theme.textMuted, "Stale metric keeps muted value")
                check(frame.tooltipText.indexOf("Last updated:") >= 0, "Tooltip must give last update")
                run("good"); test.stage = 2
            } else if (test.stage === 2 && !poll.stale && !poll.running) {
                run("fail"); test.stage = 3
            } else if (test.stage === 3 && poll.stale && !poll.running) {
                check(poll.output.indexOf("42") >= 0 && poll.error.indexOf("7") >= 0, "Failure preserves last value")
                run("invalid"); test.stage = 4
            } else if (test.stage === 4 && poll.error === "Invalid JSON output" && !poll.running) {
                run("noisy"); test.stage = 5
            } else if (test.stage === 5 && !poll.stale && !poll.running) {
                check(JSON.parse(poll.output).text === "43", "Noise discarded; stderr excluded")
                check(frame.foreground === theme.critical, "Normal foreground recovers")
                poll.interval = 1000
                poll.lastUpdated = Date.now() - 4000
                poll.now = Date.now()
                check(poll.stale && frame.foreground === theme.textMuted, "Three missed intervals mark data stale")
                poll.interval = 0
                // Wait long enough for an escaped timeout descendant to leave evidence.
                test.stage = 6; test.ticks = 0
            } else if (test.stage === 6 && test.ticks > 60) {
                console.log("SCRIPT_POLLER_PASSED"); Qt.quit()
            }
        }
    }
}
