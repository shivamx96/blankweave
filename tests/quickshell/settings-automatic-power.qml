import QtQuick
import Quickshell
import Quickshell.Io
import "Services"
import "Settings"

ShellRoot {
    id: test
    property int step: 0
    property bool recoveringStartup: true
    readonly property string fixture: Qt.resolvedUrl("power.py").toString().replace("file://", "")
    Theme { id: theme }
    PowerService { id: backend; helper: "/missing-startup-power-helper"; automaticInterval: 250; settingsActive: window.visible }
    FloatingWindow {
        id: window
        visible: true; implicitWidth: 640; implicitHeight: 700
        SettingsAutomaticPower { id: controls; theme: theme; backend: backend; width: 500 }
    }
    Process { id: changeSource; command: ["python3", test.fixture, "fixture-source"] }
    function check(condition, message) { if (!condition) throw new Error("Step " + step + ": " + message) }
    function find(parent, name) {
        if (parent.objectName === name) return parent
        for (const child of parent.children || []) { const result = find(child, name); if (result) return result }
        return null
    }
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (backend.busy || changeSource.running) return
            try {
                if (test.recoveringStartup) {
                    test.check(!backend.ready && backend.error !== "", "Missing startup helper was not detected")
                    backend.helper = test.fixture
                    test.recoveringStartup = false
                    return
                }
                if (!backend.ready) return
                const toggle = test.find(controls, "automaticPowerToggle")
                const ac = test.find(controls, "automaticPower_ac")
                const threshold = test.find(controls, "automaticPowerThreshold")
                switch (test.step) {
                case 0:
                    test.check(backend.ready && !backend.error && backend.automatic.ready && !backend.automaticEnabled, "Startup defaults not loaded")
                    test.check(toggle.enabled && ac.currentIndex === 1, "Automatic controls unavailable")
                    ac.popup.open()
                    test.check(backend.automaticMenuOpen, "Automatic menu does not pause refresh")
                    backend.refresh()
                    test.check(!backend.busy, "Refresh interrupted open menu")
                    ac.activated(2); ac.popup.close()
                    break
                case 1:
                    test.check(backend.automatic.settings.ac === "performance" && ac.currentIndex === 2, "Saved profile missing")
                    toggle.clicked()
                    test.check(!backend.automaticEnabled && backend.busy, "Optimistically enabled automation")
                    window.visible = false
                    break
                case 2:
                    if (backend.profile !== "performance") return
                    test.check(backend.automaticEnabled && !backend.active, "Automatic work requires Settings to stay open")
                    changeSource.running = true
                    break
                case 3:
                    if (backend.profile !== "power-saver") return
                    test.check(backend.automatic.source.onBattery, "Hidden background runner missed battery transition")
                    threshold.activated(3)
                    break
                case 4:
                    test.check(backend.automatic.settings.threshold === 20, "Threshold not persisted")
                    threshold.activated(6)
                    break
                case 5:
                    test.check(backend.automaticError.includes("denied") && backend.automatic.settings.threshold === 20, "Failed save accepted")
                    backend.select("balanced")
                    break
                case 6:
                    test.check(!backend.automaticEnabled && backend.profile === "balanced", "Manual choice did not disable automation")
                    test.check(!toggle.selected, "Automatic toggle stale after manual choice")
                    backend.automatic = Object.assign({}, backend.automatic, {source: {available: false}})
                    test.check(!toggle.enabled, "Enabled automation without a battery")
                    backend.automatic = Object.assign({}, backend.automatic, {settings: Object.assign({}, backend.automatic.settings, {enabled: true})})
                    test.check(toggle.enabled, "Cannot disable when battery disappears")
                    toggle.clicked()
                    break
                case 7:
                    // The deliberate out-of-band fixture mutation is rejected by CAS.
                    test.check(backend.automaticError.includes("stale") && !backend.automaticEnabled, "Stale preference overwrite was accepted")
                    console.log("SETTINGS_AUTOMATIC_POWER_PASSED")
                    Qt.quit()
                    break
                }
                test.step++
            } catch (error) { console.error(error); Qt.quit() }
        }
    }
}
