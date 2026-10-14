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
    PowerService { id: power }
    AudioService { id: audio }
    Voxtype { id: voice }
    QtObject {
        id: networkProvider
        property int backend: NetworkBackendType.NetworkManager
        property bool wifiEnabled: true
        property bool wifiHardwareEnabled: true
        property QtObject devices: QtObject { property var values: [] }
    }
    WirelessControls { id: wireless; wifi: wifi; bluetooth: bluetooth; connections: connections }
    NetworkConnections { id: connections }
    NetworkWifi { id: wifi; provider: networkProvider }
    QtObject {
        id: bluetoothProvider
        property var defaultAdapter: null
        property QtObject devices: QtObject { property var values: [] }
    }
    BluetoothService { id: bluetooth; provider: bluetoothProvider }
    SettingsWindow { id: settings; theme: desktopTheme; preferences: preferences; power: power; sound: audio; voice: voice; wifi: wifi; connections: connections; wireless: wireless; bluetooth: bluetooth }
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
                if (wifi.scanOwners.length !== 1 || !wifi.profilesActive || !bluetooth.settingsActive || !connections.settingsActive || !wireless.active) { console.error("Wi-Fi not active on Network page"); Qt.quit(); return }
                settings.selectedPage = "appearance"
            } else if (root.step === 8) {
                if (wifi.scanOwners.length || wifi.profilesActive || bluetooth.settingsActive || bluetooth.scanOwners.length || connections.settingsActive || wireless.active) { console.error("Wi-Fi active outside Network page"); Qt.quit(); return }
                settings.selectedPage = "network"; settings.minimized = true
            } else if (root.step === 9) {
                if (wifi.scanOwners.length || wifi.profilesActive || bluetooth.settingsActive || bluetooth.scanOwners.length || connections.settingsActive || wireless.active) { console.error("Wi-Fi active while minimized"); Qt.quit(); return }
                settings.minimized = false; settings.visible = false
            } else if (root.step === 10) {
                settings.selectedPage = "power"; settings.openSettings()
            } else if (root.step === 11) {
                if (!power.active || !settings.battery.active || !settings.idle.active) { console.error("Power inactive on visible page"); Qt.quit(); return }
                settings.minimized = true
            } else if (root.step === 12) {
                if (power.active || settings.battery.active || settings.idle.active) { console.error("Power active while minimized"); Qt.quit(); return }
                settings.minimized = false; settings.selectedPage = "appearance"
            } else if (root.step === 13) {
                if (power.active || settings.battery.active || settings.idle.active) { console.error("Power active on another page"); Qt.quit(); return }
                settings.selectedPage = "power"; settings.visible = false
            } else if (root.step === 14) {
                settings.selectedPage = "input"; settings.openSettings()
            } else if (root.step === 15) {
                if (!settings.pointer.active || !settings.keyboard.active) { console.error("Input backend inactive on visible Input page"); Qt.quit(); return }
                settings.minimized = true
            } else if (root.step === 16) {
                if (settings.pointer.active || settings.keyboard.active) { console.error("Input backend active while minimized"); Qt.quit(); return }
                settings.minimized = false; settings.visible = false
            } else {
                if (settings.pointer.active || settings.keyboard.active) { console.error("Input backend active while hidden"); Qt.quit(); return }
                if (power.active || settings.battery.active || settings.idle.active) { console.error("Power active while hidden"); Qt.quit(); return }
                if (wifi.scanOwners.length || wifi.profilesActive || bluetooth.settingsActive || bluetooth.scanOwners.length || connections.settingsActive || wireless.active) { console.error("Wi-Fi active while hidden"); Qt.quit(); return }
                if (audio.microphone.active) { console.error("Microphone meter requested while hidden"); Qt.quit(); return }
                console.log("SETTINGS_WINDOW_PASSED")
                Qt.quit()
            }
            root.step++
        }
    }
}
