pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var theme
    required property var backend
    readonly property bool writable: backend && backend.ready && !backend.busy
    readonly property var modes: ["off", "always", "schedule"]
    readonly property var temperatures: [2500, 3000, 3500, 4000, 4500, 5000, 5500, 6000, 6500]
    spacing: 12
    function load() {
        if (!backend) return
        mode.currentIndex = modes.indexOf(backend.preferences.mode)
        temperature.currentIndex = temperatures.indexOf(backend.preferences.temperature)
        start.text = backend.preferences.start
        end.text = backend.preferences.end
    }
    Component.onCompleted: load()
    onBackendChanged: load()
    Connections {
        target: root.backend
        ignoreUnknownSignals: true
        function onRevisionChanged() { root.load() }
    }
    RowLayout {
        Layout.fillWidth: true
        SettingsComboBox {
            id: mode
            objectName: "nightLightMode"
            Layout.fillWidth: true
            theme: root.theme
            model: ["Off", "Always on", "Scheduled"]
            enabled: root.writable
            Accessible.name: "Night light mode"
        }
        SettingsComboBox {
            id: temperature
            objectName: "nightLightTemperature"
            Layout.fillWidth: true
            theme: root.theme
            model: root.temperatures.map(value => value + " K")
            enabled: root.writable && mode.currentIndex !== 0
            Accessible.name: "Night light temperature; lower is warmer"
        }
    }
    RowLayout {
        visible: mode.currentIndex === 2
        Layout.fillWidth: true
        Text { text: "From"; color: root.theme.textMuted; font.family: root.theme.fontFamily }
        TextField {
            id: start
            objectName: "nightLightStart"
            Layout.fillWidth: true
            implicitHeight: 36
            enabled: root.writable
            maximumLength: 5
            placeholderText: "21:00"
            color: root.theme.text
            placeholderTextColor: root.theme.textMuted
            selectionColor: root.theme.accentSurface
            selectedTextColor: root.theme.text
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.textSize
            leftPadding: 10
            Accessible.name: "Night light start time, 24 hour"
            background: Rectangle { color: root.theme.surfaceRaised; radius: root.theme.widgetRadius; border.color: start.activeFocus ? root.theme.accentBright : root.theme.outline }
        }
        Text { text: "to"; color: root.theme.textMuted; font.family: root.theme.fontFamily }
        TextField {
            id: end
            objectName: "nightLightEnd"
            Layout.fillWidth: true
            implicitHeight: 36
            enabled: root.writable
            maximumLength: 5
            placeholderText: "07:00"
            color: root.theme.text
            placeholderTextColor: root.theme.textMuted
            selectionColor: root.theme.accentSurface
            selectedTextColor: root.theme.text
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.textSize
            leftPadding: 10
            Accessible.name: "Night light end time, 24 hour"
            background: Rectangle { color: root.theme.surfaceRaised; radius: root.theme.widgetRadius; border.color: end.activeFocus ? root.theme.accentBright : root.theme.outline }
        }
    }
    RowLayout {
        SettingsButton {
            objectName: "applyNightLight"
            theme: root.theme
            text: "Apply"
            enabled: root.writable && mode.currentIndex >= 0 && temperature.currentIndex >= 0
                && (mode.currentIndex === 0 || root.backend.available)
            onClicked: root.backend.apply(root.modes[mode.currentIndex], root.temperatures[temperature.currentIndex], start.text, end.text)
        }
        SettingsButton {
            theme: root.theme
            text: "Retry"
            visible: root.backend !== null && Boolean(root.backend.error)
            enabled: root.backend !== null && !root.backend.busy
            onClicked: root.backend.retry()
        }
        Text {
            Layout.fillWidth: true
            text: root.backend ? root.backend.description : "Checking night-light support…"
            textFormat: Text.PlainText
            color: root.theme.textMuted
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.smallTextSize
            wrapMode: Text.WordWrap
        }
    }
}
