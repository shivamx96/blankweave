pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var theme
    required property var backend
    readonly property bool ready: backend !== null && backend.ready && backend.available
    readonly property var profiles: ready ? backend.profiles : []
    property var menuProfiles: []
    property string menuService: ""
    property string menuOwner: ""
    property bool selecting: false
    readonly property var choices: selecting ? menuProfiles : profiles
    readonly property int selectedIndex: ready ? choices.findIndex(row => row.id === backend.profile) : -1
    spacing: 12
    Binding { target: root.backend; property: "menuOpen"; value: selector.popup.visible; when: root.backend !== null }

    SettingsComboBox {
        id: selector
        objectName: "powerProfileChoice"
        Layout.fillWidth: true
        theme: root.theme
        model: root.choices.map(row => row.name)
        currentIndex: root.selectedIndex
        displayText: currentIndex >= 0 ? currentText : "No active profile"
        enabled: root.ready && !root.backend.busy && root.choices.length > 0
        Accessible.name: "Power profile"
        onActivated: index => {
            const row = root.choices[index]
            if (row) root.backend.select(row.id, root.selecting ? root.menuService : root.backend.service,
                                        root.selecting ? root.menuOwner : root.backend.owner)
            currentIndex = Qt.binding(() => root.selectedIndex)
        }
    }
    Connections {
        target: selector.popup
        function onAboutToShow() {
            root.menuProfiles = root.profiles.slice()
            root.menuService = root.backend.service; root.menuOwner = root.backend.owner
            root.selecting = true
        }
        function onClosed() { Qt.callLater(() => { if (!selector.popup.visible) root.selecting = false }) }
    }
    Text {
        objectName: "powerProfileStatus"
        Layout.fillWidth: true
        text: root.backend && root.backend.error ? root.backend.error
            : root.backend && root.backend.busy ? "Updating power profiles…"
            : root.backend ? root.backend.explanation : "Power profiles are unavailable."
        textFormat: Text.PlainText
        color: root.backend && root.backend.error ? root.theme.critical : root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        visible: root.ready && text !== ""
        text: root.ready ? root.backend.degradation : ""
        color: root.theme.warning
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    Repeater {
        model: root.ready ? root.backend.holds : []
        delegate: Text {
            required property var modelData
            Layout.fillWidth: true
            text: (modelData.application || "An application") + " · " + modelData.reason
            textFormat: Text.PlainText
            color: root.theme.textMuted
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.smallTextSize
            wrapMode: Text.WordWrap
        }
    }
    Text {
        Layout.fillWidth: true
        visible: root.ready && root.backend.holds.length > 0
        text: "Choosing another profile releases application profile holds."
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        visible: root.backend !== null && root.backend.automaticEnabled
        text: "Choosing a profile manually turns automatic switching off."
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    SettingsButton {
        objectName: "powerProfileRefresh"
        theme: root.theme
        text: "Refresh"
        enabled: root.backend !== null && !root.backend.busy
        onClicked: root.backend.refresh(true)
    }
}
