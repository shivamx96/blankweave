import QtQuick
import Quickshell
import "Services"
import "Settings"
import "Modules"

ShellRoot {
    id: test
    property int step: 0
    readonly property string fixture: Qt.resolvedUrl("power.py").toString().replace("file://", "")
    Theme { id: theme }
    PowerService { id: backend; helper: test.fixture }
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 680
        implicitHeight: 600
        property bool atBottom: false
        property var tooltipTarget: null
        function setVisibilityHold(owner, held) {}
        function hideTooltip(owner) {}
        function showTooltip(owner, text) {}
        SettingsPowerProfiles { id: controls; theme: theme; backend: backend; width: 460 }
        BatteryWidget { id: battery; theme: theme; bar: window; power: backend; visible: false }
    }
    function check(condition, message) { if (!condition) throw new Error(message) }
    function find(parent, name) {
        if (parent.objectName === name) return parent
        for (const child of parent.children || []) { const result = find(child, name); if (result) return result }
        return null
    }
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (backend.busy) return
            try {
                const choice = test.find(controls, "powerProfileChoice")
                switch (test.step++) {
                case 0:
                    test.check(!backend.active && backend.ready && !backend.automaticEnabled, "Startup preferences were not read")
                    backend.settingsActive = true
                    break
                case 1:
                    test.check(backend.ready && backend.profile === "balanced" && choice.currentIndex === 1, "Initial profile missing")
                    test.check(backend.degradation.includes("hot") && backend.holds.length === 1, "Power limits missing")
                    choice.popup.open()
                    test.check(backend.menuOpen, "Menu does not hold polling")
                    backend.refresh()
                    test.check(!backend.busy, "Polling interrupted the open menu")
                    backend.profiles = backend.profiles.slice().reverse()
                    test.check(controls.choices[0].id === "power-saver", "Open menu was retargeted by refresh")
                    choice.activated(0)
                    choice.popup.close()
                    test.check(backend.busy && backend.profile === "balanced", "Optimistic profile write")
                    break
                case 2:
                    test.check(backend.profile === "power-saver" && choice.currentIndex === 0, "Profile not read back")
                    choice.activated(2)
                    break
                case 3:
                    test.check(backend.error.includes("denied") && backend.profile === "power-saver" && choice.currentIndex === 0, "Failed profile accepted")
                    backend.select("balanced", backend.service, ":1.old")
                    test.check(backend.error.includes("changed") && !backend.busy, "Stale menu accepted")
                    backend.profiles = backend.profiles.filter(row => row.id !== "performance")
                    test.check(!backend.canSelect("performance"), "Missing performance profile enabled")
                    backend.select("performance")
                    test.check(!backend.busy, "Unsupported profile was written")
                    backend.helper = "/nonexistent/power-profiles.py"
                    backend.refresh(true)
                    break
                case 4:
                    test.check(!backend.ready && !choice.enabled && choice.currentIndex === -1, "Failure retained profile selection")
                    backend.helper = test.fixture
                    backend.refresh(true)
                    break
                case 5:
                    test.check(backend.ready && !backend.error && choice.enabled, "Recovery failed")
                    window.tooltipTarget = battery
                    backend.settingsActive = false
                    test.check(backend.active, "Closing one view stopped shared polling")
                    window.tooltipTarget = null
                    test.check(!backend.active, "Closing last view retained polling")
                    backend.select("balanced")
                    break
                case 6:
                    test.check(backend.profile === "balanced" && !backend.busy, "Closed-view write not verified")
                    backend.available = false
                    test.check(!choice.enabled && choice.currentIndex === -1 && backend.explanation.includes("unavailable"), "Unavailable service shown as live")
                    backend.available = true
                    backend.degraded = "future-reason"
                    test.check(backend.degradation.includes("limiting"), "Unknown degradation hidden")
                    console.log("SETTINGS_POWER_PASSED")
                    Qt.quit()
                }
            } catch (error) { console.error(error); Qt.quit() }
        }
    }
}
