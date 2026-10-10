import QtQuick
import Quickshell
import "../Services"

FloatingWindow {
    id: root
    required property var theme
    required property var preferences
    property var sound: null
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

    SettingsContent {
        id: content
        anchors.fill: parent
        theme: root.theme
        appearance: appearanceBackend
        displays: displaysBackend
        sound: root.sound
        onCloseRequested: root.visible = false
    }
}
