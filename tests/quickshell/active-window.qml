import QtQuick
import Quickshell
import "Modules"

ShellRoot {
    id: test

    function compare(actual, expected) {
        if (actual !== expected)
            throw new Error("Expected " + expected + ", got " + actual)
    }

    Component.onCompleted: Qt.callLater(runTests)

    function runTests() {
        try {
            const cases = [
                test_empty_workspace_clears_cached_window,
                test_return_to_same_window_restores_display,
                test_xwayland_focus_restores_class,
                test_null_window,
                test_zero_address_clears_focus,
                test_unrelated_events_preserve_focus_state
            ]
            for (const testCase of cases) {
                init()
                testCase()
            }
            console.log("ACTIVE_WINDOW_PASSED")
        } catch (error) {
            console.error(error.stack || error)
        }
        Qt.quit()
    }

    QtObject {
        id: compositor
        property var activeToplevel: null
        signal rawEvent(var event)
    }

    QtObject {
        id: bar
        property bool atBottom: false
        function hideTooltip(target) {}
    }

    QtObject {
        id: window
        property string title: "Example application"
        property var wayland: ({ appId: "blankweave-test-missing-app" })
        property var lastIpcObject: ({ class: "blankweave-test-xwayland" })
    }

    ActiveWindowWidget {
        id: widget
        hyprland: compositor
        bar: bar
        theme: ({
            barIconSize: 16, widgetPadding: 8, widgetHeight: 28,
            widgetContentGap: 6, critical: "red", accentBright: "cyan",
            text: "white", fontFamily: "sans-serif", iconFontFamily: "sans-serif", textSize: 13
        })
    }

    function init() {
        window.title = "Example application"
        window.wayland = { appId: "blankweave-test-missing-app" }
        compositor.activeToplevel = window
        compositor.rawEvent({ name: "activewindowv2", data: "abc123" })
    }

    function verifyDesktop() {
        compare(widget.activeWindow, null)
        compare(widget.label, "Desktop")
        compare(widget.appId, "")
        compare(widget.appEntry, null)
        compare(widget.appIcon.toString(), "")
        compare(widget.icon, "󰇄")
        compare(widget.tooltip, "No active window")
    }

    function test_empty_workspace_clears_cached_window() {
        compare(widget.label, window.title)
        compare(widget.appId, window.wayland.appId)
        compositor.rawEvent({ name: "activewindowv2", data: "" })
        compare(compositor.activeToplevel, window)
        verifyDesktop()
        window.title = "Background title update"
        verifyDesktop()
    }

    function test_return_to_same_window_restores_display() {
        compositor.rawEvent({ name: "activewindowv2", data: "" })
        verifyDesktop()
        compositor.rawEvent({ name: "activewindowv2", data: "abc123" })
        compare(widget.activeWindow, window)
        compare(widget.label, window.title)
        compare(widget.appId, window.wayland.appId)
        compare(widget.icon, "󰖯")
        compare(widget.tooltip, window.title)
    }

    function test_xwayland_focus_restores_class() {
        window.wayland = null
        compositor.rawEvent({ name: "activewindowv2", data: "" })
        verifyDesktop()
        compositor.rawEvent({ name: "activewindowv2", data: "0xabc123" })
        compare(widget.appId, window.lastIpcObject.class)
        compare(widget.label, window.title)
    }

    function test_null_window() {
        compositor.activeToplevel = null
        verifyDesktop()
    }

    function test_zero_address_clears_focus() {
        compositor.rawEvent({ name: "activewindowv2", data: "0x0" })
        verifyDesktop()
    }

    function test_unrelated_events_preserve_focus_state() {
        compositor.rawEvent({ name: "workspacev2", data: "2,2" })
        compare(widget.activeWindow, window)
        compositor.rawEvent({ name: "activewindowv2", data: "" })
        compositor.rawEvent({ name: "windowtitlev2", data: "abc123,New title" })
        verifyDesktop()
    }
}
