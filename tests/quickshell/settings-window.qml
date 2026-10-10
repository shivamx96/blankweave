import QtQuick
import Quickshell
import Quickshell.Networking
import "Services"
import "Settings"

ShellRoot {
    id: root
    property int step: 0
    Theme { id: desktopTheme }
    ShellPreferences { id: preferences }
    AudioService { id: audio }
    Voxtype { id: voice }
    QtObject {
        id: networkProvider
        property int backend: NetworkBackendType.NetworkManager
        property bool wifiEnabled: true
        property bool wifiHardwareEnabled: true
        property QtObject devices: QtObject { property var values: [] }
    }
    NetworkWifi { id: wifi; provider: networkProvider }
    SettingsWindow { id: settings; theme: desktopTheme; preferences: preferences; sound: audio; voice: voice; wifi: wifi }
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
            } else if (root.step === 2) { settings.selectedPage = "sound"; settings.openSettings() }
            else if (root.step === 3) {
                if (!audio.microphone.active) { console.error("Microphone meter not requested on Sound"); Qt.quit(); return }
                settings.selectedPage = "appearance"
            } else if (root.step === 4) {
                if (audio.microphone.active) { console.error("Microphone meter requested outside Sound"); Qt.quit(); return }
                settings.selectedPage = "sound"
                settings.minimized = true
            } else if (root.step === 5) {
                if (audio.microphone.active) { console.error("Microphone meter requested while minimized"); Qt.quit(); return }
                settings.minimized = false
                settings.visible = false
            } else if (root.step === 6) {
                settings.selectedPage = "network"; settings.openSettings()
            } else if (root.step === 7) {
                if (wifi.scanOwners.length !== 1 || !wifi.profilesActive) { console.error("Wi-Fi not active on Network page"); Qt.quit(); return }
                settings.selectedPage = "appearance"
            } else if (root.step === 8) {
                if (wifi.scanOwners.length || wifi.profilesActive) { console.error("Wi-Fi active outside Network page"); Qt.quit(); return }
                settings.selectedPage = "network"; settings.minimized = true
            } else if (root.step === 9) {
                if (wifi.scanOwners.length || wifi.profilesActive) { console.error("Wi-Fi active while minimized"); Qt.quit(); return }
                settings.minimized = false; settings.visible = false
            } else {
                if (wifi.scanOwners.length || wifi.profilesActive) { console.error("Wi-Fi active while hidden"); Qt.quit(); return }
                if (audio.microphone.active) { console.error("Microphone meter requested while hidden"); Qt.quit(); return }
                console.log("SETTINGS_WINDOW_PASSED")
                Qt.quit()
            }
            root.step++
        }
    }
}
