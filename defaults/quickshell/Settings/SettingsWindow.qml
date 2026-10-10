import QtQuick
import Quickshell
import "../Services"

FloatingWindow {
    id: root
    required property var theme
    required property var preferences
    property var sound: null
    property var voice: null
    property var wifi: null
    readonly property bool wifiActive: visible && !minimized && content.page !== null && content.page.id === "network"
    onWifiActiveChanged: if (wifi) wifi.setScanRequest(root, wifiActive)
    Component.onDestruction: if (wifi) wifi.setScanRequest(root, false)
    Binding { target: root.wifi; property: "profilesActive"; value: root.wifiActive; when: root.wifi !== null }
    property alias selectedPage: content.selectedPage
    visible: false
    title: "Blankweave Settings"
    implicitWidth: 1040
    implicitHeight: 760
    minimumSize: Qt.size(640, 480)
    color: theme.canvas

    function openSettings() {
        // Remapping an existing window also brings it back from another workspace.
        visible = false
        visible = true
        minimized = false
        appearanceBackend.refresh()
        content.focusSearch()
    }

    SettingsAppearance {
        id: appearanceBackend
        theme: root.theme
        preferences: root.preferences
    }

    SettingsNightLight { id: nightLightBackend }
    SettingsSystemSounds {
        id: systemSoundsBackend
        active: root.visible && !root.minimized && content.page !== null && content.page.id === "sound"
    }

    SettingsDisplays {
        id: displaysBackend
        active: root.visible && content.page !== null && content.page.id === "displays"
        brightness: displayBrightness
        nightLight: nightLightBackend
    }

    DisplayBrightness {
        id: displayBrightness
        screen: displaysBackend.monitor
        active: displaysBackend.active && displaysBackend.monitor !== null
    }

    Binding {
        target: root.sound ? root.sound.microphone : null
        property: "active"
        value: root.visible && !root.minimized && content.page !== null && content.page.id === "sound"
        when: root.sound !== null && Boolean(root.sound.microphone)
    }

    SettingsContent {
        id: content
        anchors.fill: parent
        theme: root.theme
        appearance: appearanceBackend
        displays: displaysBackend
        sound: root.sound
        voice: root.voice
        wifi: root.wifi
        systemSounds: systemSoundsBackend
        onCloseRequested: root.visible = false
    }
}
