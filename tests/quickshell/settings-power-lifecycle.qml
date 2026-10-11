import QtQuick
import Quickshell
import Quickshell.Io
import "Services"
import "Settings"

ShellRoot {
    id: test
    property int phase: 0
    property int scenario: 0
    property int waiting: 0
    property var choice: null
    readonly property var menus: ["powerProfileChoice", "automaticPower_ac", "automaticPower_battery", "automaticPower_low", "automaticPowerThreshold"]
    readonly property string hideMode: ["hidden", "minimized"][Math.floor(scenario / menus.length)] || "complete"
    Theme { id: theme }
    ShellPreferences { id: preferences }
    PowerService { id: backend; automaticInterval: 250 }
    SettingsWindow { id: settings; theme: theme; preferences: preferences; power: backend; selectedPage: "power" }
    Process { id: changeSource }
    function find(parent, name) {
        if (parent.objectName === name) return parent
        for (const child of parent.children || []) { const result = find(child, name); if (result) return result }
        return null
    }
    function check(condition, message) {
        if (!condition) throw new Error(menus[scenario % menus.length] + " / " + hideMode + ": " + message)
    }
    function source(command) {
        // Keep fixture source changes separate from the timer's read/write cycle.
        backend.automaticInterval = 60000
        changeSource.command = ["python3", backend.helper, command]
        changeSource.running = true
    }
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (!preferences.ready || backend.busy || changeSource.running) return
            try {
                switch (test.phase) {
                case 0:
                    if (!backend.ready) return
                    settings.openSettings()
                    backend.configureAutomatic({enabled: true, ac: "performance", low: "power-saver"})
                    break
                case 1:
                    if (backend.profile !== "performance") return
                    test.choice = test.find(settings.contentItem, test.menus[test.scenario % test.menus.length])
                    test.check(test.choice !== null, "Dropdown missing")
                    test.choice.popup.open()
                    test.check(backend.menuOpen || backend.automaticMenuOpen, "Menu pause not registered")
                    backend.tick()
                    backend.refresh()
                    test.check(!backend.busy, "Visible menu did not pause work")
                    if (test.hideMode === "hidden") settings.visible = false
                    else settings.minimized = true
                    test.check(!backend.settingsActive, "Settings still active")
                    test.source("fixture-source")
                    test.waiting = 0
                    break
                case 2:
                    backend.automaticInterval = 250
                    if (backend.profile !== "power-saver") {
                        test.check(test.waiting++ < 30, "Low-battery transition was blocked by a hidden dropdown")
                        return
                    }
                    test.check(backend.automatic.source.onBattery, "Battery transition not read back")
                    test.choice.popup.close()
                    settings.openSettings()
                    test.source("fixture-ac")
                    break
                case 3:
                    backend.automaticInterval = 250
                    if (backend.profile !== "performance") return
                    test.scenario++
                    if (test.scenario === test.menus.length * 2) {
                        console.log("SETTINGS_POWER_LIFECYCLE_PASSED")
                        Qt.quit()
                        return
                    }
                    test.phase = 1
                    return
                }
                test.phase++
            } catch (error) { console.error(error); Qt.quit() }
        }
    }
}
