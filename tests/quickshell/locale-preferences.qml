import QtQuick
import Quickshell
import "../../defaults/quickshell/Services"
ShellRoot {
    ShellPreferences { id: preferences }
    property int step: 0
    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            if (!preferences.ready) return
            if (step === 0) {
                if (preferences.welcomeShown !== false) throw new Error("Welcome must default to unseen")
                preferences.welcomeShown = true
                preferences.timeFormat = "12h"
                preferences.temperatureUnit = "fahrenheit"
            } else if (step === 1) {
                const saved = JSON.parse(preferences.file.text())
                if (saved.welcomeShown !== true || saved.timeFormat !== "12h" || saved.temperatureUnit !== "fahrenheit")
                    throw new Error("Preferences did not persist")
                preferences.timeFormat = "invalid"
                preferences.temperatureUnit = "kelvin"
            } else {
                const saved = JSON.parse(preferences.file.text())
                if (preferences.timeFormat !== "auto" || preferences.temperatureUnit !== "auto"
                    || saved.timeFormat !== "auto" || saved.temperatureUnit !== "auto")
                    throw new Error("Unknown preference did not normalize")
                Qt.quit()
            }
            step++
        }
    }
}
