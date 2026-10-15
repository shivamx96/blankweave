pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import "../Components"
ColumnLayout {
    id: root
    required property var theme
    required property var backend
    property string selectedId: ""
    readonly property var rows: backend && backend.ready ? backend.data.rows : []
    readonly property var selected: selectedId ? rows.find(r => r.id === selectedId) || null : (rows.length ? rows[0] : null)
    property string draftPath: ""
    property string draftFit: "crop"
    property string draftRevision: ""
    property string draftId: ""
    function beginEdit() {
        if (!draftRevision && selected) { draftRevision = backend.data.revision; draftId = selected.id; draftPath = selected.path; draftFit = selected.fit }
    }
    spacing: 10
    SettingsComboBox {
        id: displayChoice
        property var menuRows: []
        property bool choosing: false
        readonly property var choices: choosing ? menuRows : root.rows
        theme: root.theme; Layout.fillWidth: true
        model: choices.map(r => r.label)
        currentIndex: root.selected ? choices.findIndex(r => r.id === root.selected.id) : -1
        enabled: root.backend && root.backend.writable && !root.draftRevision
        Accessible.name: "Wallpaper display"
        onActivated: index => { if (choices[index]) root.selectedId = choices[index].id; currentIndex = Qt.binding(() => root.selected ? choices.findIndex(r => r.id === root.selected.id) : -1) }
    }
    Connections {
        target: displayChoice.popup
        function onAboutToShow() { displayChoice.menuRows = root.rows.slice(); displayChoice.choosing = true }
        function onClosed() { Qt.callLater(() => { if (!displayChoice.popup.visible) displayChoice.choosing = false }) }
    }
    Text {
        Layout.fillWidth: true
        text: root.selected ? (root.selected.custom ? "Custom image: " : "Theme image: ") + root.selected.path : "No connected displays."
        textFormat: Text.PlainText; color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WrapAnywhere
    }
    SettingsButton { theme: root.theme; text: "Choose image…"; enabled: root.backend && root.backend.writable && root.selected !== null; onClicked: { root.beginEdit(); imageDialog.open() } }
    FileDialog {
        id: imageDialog
        title: "Choose wallpaper"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp)"]
        onAccepted: {
            const url = selectedFile.toString()
            if (url.startsWith("file://")) root.draftPath = decodeURIComponent(url.slice(7))
        }
    }
    ControlTextField { theme: root.theme; Layout.fillWidth: true; visible: root.draftRevision !== ""; text: root.draftPath; Accessible.name: "Wallpaper image path"; onTextEdited: root.draftPath = text }
    SettingsComboBox {
        theme: root.theme; Layout.fillWidth: true
        model: ["Fill (crop)", "Fit", "Stretch", "Center"]
        currentIndex: ["crop", "fit", "stretch", "no"].indexOf(root.draftRevision ? root.draftFit : root.selected ? root.selected.fit : "crop")
        enabled: root.backend && root.backend.writable && root.selected !== null
        Accessible.name: "Wallpaper fit"
        onActivated: index => { root.beginEdit(); root.draftFit = ["crop", "fit", "stretch", "no"][index]; currentIndex = Qt.binding(() => ["crop", "fit", "stretch", "no"].indexOf(root.draftRevision ? root.draftFit : root.selected ? root.selected.fit : "crop")) }
    }
    RowLayout {
        SettingsButton { theme: root.theme; text: "Apply"; enabled: root.backend && root.backend.writable && root.draftRevision !== ""; onClicked: { root.backend.apply({action: "set", id: root.draftId, path: root.draftPath, fit: root.draftFit}, root.draftRevision); root.draftRevision = "" } }
        SettingsButton { theme: root.theme; text: "Cancel edit"; visible: root.draftRevision !== ""; onClicked: root.draftRevision = "" }
        SettingsButton { theme: root.theme; text: "Use theme wallpaper"; enabled: root.backend && root.backend.writable && root.selected !== null && root.selected.custom; onClicked: root.backend.apply({action: "reset", id: root.selected.id}) }
    }
    SettingsTaskStatus { theme: root.theme; backend: root.backend }
}
