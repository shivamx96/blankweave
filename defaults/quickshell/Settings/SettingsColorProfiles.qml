pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var theme
    required property var backend
    readonly property bool writable: backend && backend.ready && !backend.busy && typeof backend.assignColorProfile === "function"
    readonly property var profiles: backend && backend.colorProfiles ? backend.colorProfiles : []
    readonly property string assigned: backend && backend.monitor ? backend.monitor.colorProfile || "" : ""
    readonly property int assignedIndex: assigned ? profiles.findIndex(row => row.path === assigned) + 1 : 0
    property string deletingId: ""
    spacing: 12
    RowLayout {
        Layout.fillWidth: true
        SettingsComboBox {
            objectName: "displayColorProfile"
            Layout.fillWidth: true
            theme: root.theme
            model: ["Default (sRGB)"].concat(root.profiles.map(row => row.name + (row.available ? "" : " (file missing)")))
            currentIndex: root.assigned && root.assignedIndex === 0 ? -1 : root.assignedIndex
            enabled: root.writable
            Accessible.name: "Assigned color profile"
            onActivated: index => {
                if (index === 0 || root.profiles[index - 1].available)
                    root.backend.assignColorProfile(index === 0 ? "none" : root.profiles[index - 1].id)
                currentIndex = Qt.binding(() => root.assigned && root.assignedIndex === 0 ? -1 : root.assignedIndex)
            }
        }
        SettingsButton {
            objectName: "importColorProfile"
            theme: root.theme
            text: "Import…"
            enabled: root.writable
            onClicked: picker.open()
        }
    }
    Text {
        Layout.fillWidth: true
        text: "Shows the saved assignment. Turn off night light when judging calibrated colors."
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    Repeater {
        model: root.profiles
        delegate: RowLayout {
            id: profile
            required property var modelData
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: profile.modelData.name
                textFormat: Text.PlainText
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.smallTextSize
                elide: Text.ElideRight
            }
            SettingsButton {
                theme: root.theme
                text: root.deletingId === profile.modelData.id ? "Confirm remove" : "Remove"
                enabled: root.writable
                onClicked: {
                    if (root.deletingId === profile.modelData.id) {
                        root.backend.deleteColorProfile(profile.modelData.id)
                        root.deletingId = ""
                    } else root.deletingId = profile.modelData.id
                }
            }
            SettingsButton {
                theme: root.theme
                text: "Cancel"
                visible: root.deletingId === profile.modelData.id
                onClicked: root.deletingId = ""
            }
        }
    }
    FileDialog {
        id: picker
        title: "Import an RGB display color profile"
        nameFilters: ["ICC profiles (*.icc *.icm *.ICC *.ICM)", "All files (*)"]
        onAccepted: if (root.writable) root.backend.importColorProfile(selectedFile.toString())
    }
}
