import QtQuick
import Quickshell
import "Services"
import "Settings"

ShellRoot {
    id: root
    property int step: 0
    Theme { id: desktopTheme }
    ShellPreferences { id: preferences }
    SettingsWindow { id: settings; theme: desktopTheme; preferences: preferences }
    Timer {
        interval: 200
        running: true
        repeat: true
        onTriggered: {
            if (!preferences.ready) return
            if (root.step === 0) {
                settings.selectedPage = "displays"
                settings.openSettings()
            }
            else if (root.step === 1) {
                if (!settings.visible) { console.error("Settings did not open"); Qt.quit(); return }
                settings.visible = false
            } else if (root.step === 2) settings.openSettings()
            else {
                if (settings.visible) console.log("SETTINGS_WINDOW_PASSED")
                Qt.quit()
            }
            root.step++
        }
    }
}
