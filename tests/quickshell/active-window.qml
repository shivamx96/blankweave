pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "Modules"
import "Services"

ShellRoot {
    id: test
    property var activeWindow: null
    property var widget: null
    property int step: 0
    property bool waiting: false
    readonly property string fixture: Qt.resolvedUrl("query.sh").toString().replace("file://", "")

    Item { id: container }

    function compare(actual, expected) {
        if (actual !== expected)
            throw new Error("Expected " + expected + ", got " + actual)
    }

    QtObject {
        id: compositor
        property var activeToplevel: window
        property QtObject toplevels: QtObject { property var values: [window] }
        signal rawEvent(var event)
    }

    QtObject {
        id: fakeBar
        property var shell: test
        property bool atBottom: false
        function hideTooltip(target) {}
    }

    QtObject {
        id: window
        property string address: "0xabc123"
        property string title: "Example application"
        property var wayland: ({ appId: "blankweave-test-missing-app" })
        property var lastIpcObject: ({ class: "blankweave-test-xwayland" })
    }

    QtObject {
        id: otherWindow
        property string address: "0xdef456"
        property string title: "Other application"
        property var wayland: null
        property var lastIpcObject: ({})
    }

    Component {
        id: serviceFactory
        ActiveWindow { hyprland: compositor }
    }

    Component {
        id: widgetFactory
        ActiveWindowWidget {
            bar: fakeBar
            theme: ({
                barIconSize: 16, widgetPadding: 8, widgetHeight: 28,
                widgetContentGap: 6, critical: "red", accentBright: "cyan",
                text: "white", fontFamily: "sans-serif", iconFontFamily: "sans-serif", textSize: 13
            })
        }
    }

    function focus(address) {
        compositor.rawEvent({ name: "activewindowv2", data: address })
    }

    function init() {
        window.address = "0xabc123"
        window.title = "Example application"
        window.wayland = { appId: "blankweave-test-missing-app" }
        window.lastIpcObject = { class: "blankweave-test-xwayland" }
        compositor.toplevels.values = [window]
        compositor.activeToplevel = window
        focus("abc123")
    }

    function verifyDesktop(target = widget) {
        compare(target.activeWindow, null)
        compare(target.label, "Desktop")
        compare(target.appId, "")
        compare(target.appEntry, null)
        compare(target.appIcon.toString(), "")
        compare(target.icon, "󰇄")
        compare(target.tooltip, "No active window")
    }

    function test_empty_workspace_clears_cached_window() {
        compare(widget.label, window.title)
        compare(widget.appId, window.wayland.appId)
        focus("")
        compare(compositor.activeToplevel, window)
        verifyDesktop()
        window.title = "Background title update"
        verifyDesktop()
    }

    function test_return_to_same_window_restores_display() {
        focus("")
        verifyDesktop()
        focus("abc123")
        compare(widget.activeWindow, window)
        compare(widget.label, window.title)
        compare(widget.appId, window.wayland.appId)
        compare(widget.icon, "󰖯")
        compare(widget.tooltip, window.title)
    }

    function test_xwayland_focus_restores_class() {
        window.wayland = null
        focus("")
        verifyDesktop()
        focus("abc123")
        compare(widget.appId, window.lastIpcObject.class)
        compare(widget.label, window.title)
    }

    function test_empty_title_uses_app_or_neutral_label() {
        window.title = ""
        compare(widget.label, window.wayland.appId)
        window.wayland = null
        compare(widget.label, window.lastIpcObject.class)
        window.lastIpcObject = {}
        compare(widget.label, "Untitled window")
        compare(widget.tooltip, "Untitled window")
        compare(widget.icon, "󰖯")
        window.title = "Resolved title"
        compare(widget.label, window.title)
    }

    function test_closed_window() {
        compositor.activeToplevel = null
        compositor.toplevels.values = []
        verifyDesktop()
    }

    function test_new_placeholder_window() {
        otherWindow.title = ""
        compositor.activeToplevel = otherWindow
        focus("def456")
        compare(widget.activeWindow, otherWindow)
        compare(widget.label, "Untitled window")
        compare(widget.icon, "󰖯")
        otherWindow.title = "New window title"
        compare(widget.label, otherWindow.title)
    }

    function test_zero_address_follows_native_state() {
        window.address = "0x0"
        focus("0")
        compare(widget.activeWindow, window)
        focus("")
        verifyDesktop()
    }

    function test_invalid_and_mismatched_addresses_are_ignored() {
        for (const address of ["garbage", "abc123junk", "def456", "10000000000000000"]) {
            focus(address)
            compare(widget.activeWindow, window)
        }
        focus("")
        for (const address of ["garbage", "abc123junk", "def456", "10000000000000000"])
            focus(address)
        verifyDesktop()
    }

    function test_addresses_keep_full_precision() {
        window.address = "0xffffffffffffffff"
        focus("ffffffffffffffff")
        compare(widget.activeWindow, window)
        focus("")
        focus("fffffffffffffffe")
        verifyDesktop()
        focus("ffffffffffffffff")
        compare(widget.activeWindow, window)
    }

    function test_unrelated_events_preserve_focus_state() {
        compositor.rawEvent({ name: "workspacev2", data: "2,2" })
        compare(widget.activeWindow, window)
        focus("")
        compositor.rawEvent({ name: "windowtitlev2", data: "abc123,New title" })
        verifyDesktop()
    }

    function test_new_bars_share_cleared_focus() {
        focus("")
        const secondWidget = widgetFactory.createObject(container)
        verifyDesktop(secondWidget)
        focus("abc123")
        compare(widget.activeWindow, window)
        compare(secondWidget.activeWindow, window)
        focus("")
        verifyDesktop()
        verifyDesktop(secondWidget)
        secondWidget.destroy()
        widget.destroy()
        widget = widgetFactory.createObject(container)
        verifyDesktop()
    }

    function runTests() {
        const cases = [
            test_empty_workspace_clears_cached_window,
            test_return_to_same_window_restores_display,
            test_xwayland_focus_restores_class,
            test_empty_title_uses_app_or_neutral_label,
            test_closed_window,
            test_new_placeholder_window,
            test_zero_address_follows_native_state,
            test_invalid_and_mismatched_addresses_are_ignored,
            test_addresses_keep_full_precision,
            test_unrelated_events_preserve_focus_state,
            test_new_bars_share_cleared_focus
        ]
        for (const testCase of cases) {
            init()
            testCase()
        }
    }

    Timer {
        interval: 20
        running: true
        repeat: true
        onTriggered: {
            try {
                const scenarios = ["empty", "empty", "focused", "focused", "delayed-focused",
                    "delayed-empty", "delayed-focused", "failed", "malformed", "invalid-address"]
                if (!test.waiting) {
                    if (test.widget) test.widget.destroy()
                    if (test.activeWindow) test.activeWindow.destroy()
                    window.address = "0xabc123"
                    compositor.activeToplevel = test.step === 2 ? null : otherWindow
                    compositor.toplevels.values = test.step === 3 ? [] : [window, otherWindow]
                    test.activeWindow = serviceFactory.createObject(container, {
                        queryCommand: ["bash", test.fixture, scenarios[test.step]]
                    })
                    test.widget = widgetFactory.createObject(container)
                    test.verifyDesktop()
                    if (test.step === 4) test.focus("")
                    if (test.step === 5) { compositor.activeToplevel = window; test.focus("abc123") }
                    if (test.step === 6) test.focus("def456")
                    test.waiting = true
                    return
                }
                if (test.activeWindow.initializing) return
                switch (test.step) {
                case 0:
                    test.verifyDesktop()
                    test.runTests()
                    break
                case 1:
                case 4:
                    test.verifyDesktop()
                    break
                case 2:
                case 5:
                    test.compare(test.widget.activeWindow, window)
                    break
                case 3:
                    test.verifyDesktop()
                    compositor.toplevels.values = [window, otherWindow]
                    test.compare(test.widget.activeWindow, window)
                    break
                case 6:
                    test.compare(test.widget.activeWindow, otherWindow)
                    break
                default:
                    test.verifyDesktop()
                    test.compare(test.activeWindow.error.length > 0, true)
                    compositor.activeToplevel = window
                    test.focus("abc123")
                    test.compare(test.widget.activeWindow, window)
                    test.compare(test.activeWindow.error, "")
                }
                test.waiting = false
                test.step++
                if (test.step === scenarios.length) {
                    console.log("ACTIVE_WINDOW_PASSED")
                    Qt.quit()
                }
            } catch (error) {
                console.error("ACTIVE_WINDOW_FAILED: " + error + "\n" + error.stack)
                Qt.quit()
            }
        }
    }
}
