pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var theme
    required property var backend
    readonly property bool ready: backend !== null && backend.ready
    property string selectedId: "browser"
    readonly property var selected: ready ? backend.rows.find(r => r.id === selectedId) || null : null
    readonly property string currentId: selected && selected.current.length && selected.current.every(a => a.id === selected.current[0].id) ? selected.current[0].id : ""
    spacing: 10
    SettingsComboBox {
        id: category
        objectName: "defaultAppCategory"
        Layout.fillWidth: true
        theme: root.theme
        property var menuRows: []
        property bool choosing: false
        readonly property var rows: choosing ? menuRows : root.ready ? root.backend.rows : []
        model: rows.map(r => r.label)
        currentIndex: rows.findIndex(r => r.id === root.selectedId)
        enabled: root.ready && !root.backend.busy
        Accessible.name: "Default application category"
        onActivated: index => {
            if (rows[index]) root.selectedId = rows[index].id
            currentIndex = Qt.binding(() => rows.findIndex(r => r.id === root.selectedId))
        }
    }
    Connections {
        target: category.popup
        function onAboutToShow() { category.menuRows = root.backend.rows.slice(); category.choosing = true }
        function onClosed() { Qt.callLater(() => { if (!category.popup.visible) category.choosing = false }) }
    }
    Text {
        Layout.fillWidth: true
        text: root.selected ? "Applies to: " + root.selected.types.join(", ") : "Select a category."
        textFormat: Text.PlainText
        color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WrapAnywhere
    }
    Repeater {
        model: root.selected ? root.selected.current : []
        delegate: Text {
            required property var modelData
            Layout.fillWidth: true
            text: modelData.type + ": " + (modelData.id ? modelData.name + " (" + modelData.id + ")" : "No registered default")
            textFormat: Text.PlainText
            color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WrapAnywhere
        }
    }
    SettingsComboBox {
        id: appChoice
        objectName: "defaultAppChoice"
        Layout.fillWidth: true
        theme: root.theme
        property var menuChoices: []
        property var snapshot: null
        property string menuCategory: ""
        property bool choosing: false
        readonly property var choices: choosing ? menuChoices : root.selected ? root.selected.choices : []
        model: choices.map(a => a.name + " (" + a.id + ")")
        currentIndex: choices.findIndex(a => a.id === root.currentId)
        displayText: currentIndex >= 0 ? currentText : choices.length ? "Choose an application…" : "No compatible applications installed"
        enabled: root.ready && root.backend.writable && choices.length > 0
        Accessible.name: "Default application"
        onActivated: index => {
            const app = choices[index]
            if (app) root.backend.apply(choosing ? menuCategory : root.selectedId, app.id, choosing ? snapshot : root.backend.snapshot())
            currentIndex = Qt.binding(() => choices.findIndex(a => a.id === root.currentId))
        }
    }
    Connections {
        target: appChoice.popup
        function onAboutToShow() {
            appChoice.menuChoices = root.selected ? root.selected.choices.slice() : []
            appChoice.snapshot = root.backend.snapshot()
            appChoice.menuCategory = root.selectedId
            appChoice.choosing = true
        }
        function onClosed() { Qt.callLater(() => { if (!appChoice.popup.visible) appChoice.choosing = false }) }
    }
    Text {
        Layout.fillWidth: true
        text: "Only installed apps registered for every listed type are offered. Changes affect compatible open-link and open-file actions. Application launch shortcuts keep their configured actions."
        color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap
    }
    SettingsButton {
        objectName: "defaultAppInherited"
        theme: root.theme; text: "Use inherited defaults"
        enabled: root.ready && root.backend.writable && root.selected !== null && root.selected.local
        onClicked: root.backend.apply(root.selectedId, null, root.backend.snapshot())
    }
    Text {
        Layout.fillWidth: true
        text: "Use inherited defaults removes this category’s entries from your user MIME preferences. Desktop-specific or system defaults then take effect."
        color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        text: root.backend === null ? "Default applications unavailable." : root.backend.error || (!root.ready ? "Loading default applications…" : root.backend.message)
        visible: text !== ""
        color: root.backend && root.backend.error ? root.theme.warning : root.theme.textMuted
        font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap
    }
    SettingsButton {
        theme: root.theme; text: "Refresh"
        enabled: root.backend !== null && !root.backend.busy
        onClicked: root.backend.refresh(true)
    }
}
