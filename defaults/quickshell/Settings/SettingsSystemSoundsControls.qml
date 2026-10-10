pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var theme
    required property var backend
    readonly property bool ready: backend !== null && Boolean(backend.ready)
    readonly property bool writable: ready && !backend.busy
    readonly property var themes: ready ? backend.themes : []
    property var menuThemes: []
    property bool selecting: false
    readonly property var choices: selecting ? menuThemes : themes
    readonly property int selectedIndex: ready ? choices.findIndex(row => row.id === backend.preferences["theme-name"]) : -1
    spacing: 12

    GridLayout {
        columns: root.width < 440 ? 1 : 2
        Layout.fillWidth: true
        SettingsButton {
            objectName: "eventSoundsToggle"
            theme: root.theme
            text: !root.ready ? "Event sounds: —" : root.backend.preferences["event-sounds"] ? "Event sounds: On" : "Event sounds: Off"
            enabled: root.writable && root.backend.writable["event-sounds"] === true
            selected: root.ready && root.backend.preferences["event-sounds"] === true
            onClicked: root.backend.apply("event-sounds", !root.backend.preferences["event-sounds"])
        }
        SettingsButton {
            objectName: "inputSoundsToggle"
            theme: root.theme
            text: !root.ready ? "Input feedback: —" : root.backend.preferences["input-feedback-sounds"] ? "Input feedback: On" : "Input feedback: Off"
            enabled: root.writable && root.backend.preferences["event-sounds"] === true
                && root.backend.writable["input-feedback-sounds"] === true
            selected: root.ready && root.backend.preferences["input-feedback-sounds"] === true
            onClicked: root.backend.apply("input-feedback-sounds", !root.backend.preferences["input-feedback-sounds"])
        }
    }
    SettingsComboBox {
        id: soundTheme
        objectName: "systemSoundTheme"
        Layout.fillWidth: true
        theme: root.theme
        model: root.choices.map(row => row.name)
        currentIndex: root.selectedIndex
        displayText: currentIndex >= 0 ? currentText : root.ready ? "Theme unavailable: " + root.backend.preferences["theme-name"] : "Loading sound themes…"
        enabled: root.writable && root.backend.writable["theme-name"] === true && root.choices.length > 0
        Accessible.name: "Sound theme"
        onActivated: index => {
            const row = root.choices[index]
            if (row) root.backend.apply("theme-name", row.id)
            currentIndex = Qt.binding(() => root.selectedIndex)
        }
    }
    Connections {
        target: soundTheme.popup
        function onAboutToShow() { root.menuThemes = root.themes.slice(); root.selecting = true }
        function onClosed() { Qt.callLater(() => { if (!soundTheme.popup.visible) root.selecting = false }) }
    }
    GridLayout {
        columns: root.width < 500 ? 1 : 3
        SettingsButton {
            objectName: "systemSoundPreview"
            theme: root.theme
            text: "Play preview"
            enabled: root.backend !== null && root.backend.canPreview
            onClicked: root.backend.preview()
        }
        SettingsButton {
            objectName: "systemSoundSync"
            theme: root.theme
            text: "Apply to apps"
            visible: root.ready && !root.backend.gtkSynced
            enabled: root.writable
            onClicked: root.backend.sync()
        }
        SettingsButton {
            objectName: "systemSoundRefresh"
            theme: root.theme
            text: "Refresh"
            enabled: root.backend !== null && !root.backend.busy
            onClicked: root.backend.refresh(true)
        }
    }
    Text {
        Layout.fillWidth: true
        objectName: "systemSoundStatus"
        text: root.backend && root.backend.error ? root.backend.error
            : !root.ready ? "Reading desktop sound settings…"
            : !root.backend.gtkSynced ? "Saved sound preferences need to be applied to apps."
            : !root.backend.previewAvailable ? "Install libcanberra to play a sound preview."
            : "Sound preferences saved. Reopen apps that do not pick up the change."
        textFormat: Text.PlainText
        color: root.backend && root.backend.error ? root.theme.critical : root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        text: "Applies to apps that support desktop event sounds. Input feedback covers sounds such as button clicks. Notification and dictation sounds are controlled separately."
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
}
