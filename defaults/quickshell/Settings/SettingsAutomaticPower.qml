pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var theme
    required property var backend
    readonly property var policy: backend ? backend.automatic : null
    readonly property bool ready: policy !== null && policy.ready
    readonly property bool enabledPolicy: ready && policy.settings.enabled
    readonly property bool writable: ready && !backend.busy
    readonly property var profiles: backend && backend.ready ? backend.profiles : []
    property var openMenus: []
    function menu(id, open) {
        const next = openMenus.filter(item => item !== id)
        if (open) next.push(id)
        openMenus = next
    }
    spacing: 12
    Binding { target: root.backend; property: "automaticMenuOpen"; value: root.openMenus.length > 0; when: root.backend !== null }

    SettingsButton {
        objectName: "automaticPowerToggle"
        theme: root.theme
        text: root.enabledPolicy ? "Automatic switching: On" : "Automatic switching: Off"
        selected: root.enabledPolicy
        enabled: root.writable && (root.enabledPolicy || (root.backend.available && root.policy.source.available))
        onClicked: root.backend.configureAutomatic({enabled: !root.enabledPolicy})
    }
    Repeater {
        model: [{id: "ac", title: "Plugged in"}, {id: "battery", title: "On battery"}, {id: "low", title: "Low battery"}]
        delegate: RowLayout {
            id: mode
            required property var modelData
            property var capturedProfiles: []
            property bool selecting: false
            readonly property var choices: selecting ? capturedProfiles : root.profiles
            readonly property int selectedIndex: root.ready ? choices.findIndex(row => row.id === root.policy.settings[modelData.id]) : -1
            Layout.fillWidth: true
            spacing: 12
            Text {
                Layout.preferredWidth: 100
                text: mode.modelData.title
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.smallTextSize
            }
            SettingsComboBox {
                id: choice
                objectName: "automaticPower_" + mode.modelData.id
                Layout.fillWidth: true
                theme: root.theme
                model: mode.choices.map(row => row.name)
                currentIndex: mode.selectedIndex
                displayText: currentIndex >= 0 ? currentText : "Profile unavailable"
                enabled: root.writable && root.profiles.length > 0
                Accessible.name: mode.modelData.title + " power profile"
                onActivated: index => {
                    const row = mode.choices[index]
                    if (row) {
                        const change = {}; change[mode.modelData.id] = row.id
                        root.backend.configureAutomatic(change)
                    }
                    currentIndex = Qt.binding(() => mode.selectedIndex)
                }
            }
            Connections {
                target: choice.popup
                function onAboutToShow() {
                    mode.capturedProfiles = root.profiles.slice(); mode.selecting = true
                    root.menu(mode.modelData.id, true)
                }
                function onClosed() {
                    root.menu(mode.modelData.id, false)
                    Qt.callLater(() => { if (!choice.popup.visible) mode.selecting = false })
                }
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        Text {
            Layout.preferredWidth: 100
            text: "Low battery at"
            color: root.theme.text
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.smallTextSize
        }
        SettingsComboBox {
            id: threshold
            objectName: "automaticPowerThreshold"
            Layout.fillWidth: true
            theme: root.theme
            readonly property var levels: [5, 10, 15, 20, 25, 30, 40, 50]
            readonly property int selectedIndex: root.ready ? levels.indexOf(root.policy.settings.threshold) : -1
            model: levels.map(level => level + "%")
            currentIndex: selectedIndex
            displayText: currentIndex >= 0 ? currentText : root.ready ? root.policy.settings.threshold + "%" : "—"
            enabled: root.writable
            Accessible.name: "Low battery threshold"
            onActivated: index => {
                root.backend.configureAutomatic({threshold: levels[index]})
                currentIndex = Qt.binding(() => threshold.selectedIndex)
            }
        }
        Connections {
            target: threshold.popup
            function onAboutToShow() { root.menu("threshold", true) }
            function onClosed() { root.menu("threshold", false) }
        }
    }
    Text {
        Layout.fillWidth: true
        objectName: "automaticPowerStatus"
        text: root.backend && root.backend.automaticError ? root.backend.automaticError
            : !root.ready ? root.policy ? root.policy.message : "Automatic profiles are unavailable."
            : !root.policy.source.available ? "Automatic profiles need a supported battery and a running UPower service."
            : root.policy.message + " Current power: " + (root.policy.source.onBattery ? "battery" : "plugged in")
                + " · " + Math.round(root.policy.source.percentage) + "%"
        textFormat: Text.PlainText
        color: root.backend && root.backend.automaticError ? root.theme.critical : root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        text: "Runs while the desktop shell is active, even with Settings closed. Checks for power-state changes every 10 seconds. Low-battery mode ends five percentage points above the threshold. Application profile holds take priority."
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
}
