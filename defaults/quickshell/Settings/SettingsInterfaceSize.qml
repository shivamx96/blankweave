pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var theme
    required property var backend
    required property string settingId
    readonly property bool cursor: settingId === "cursor"
    readonly property string key: cursor ? "cursor_size" : "text_scale"
    readonly property var values: cursor ? [24, 32, 48] : [1, 1.15, 1.3]
    readonly property bool ready: backend !== null && backend.ready
    property var snapshot: null
    spacing: 10
    SettingsComboBox {
        id: sizeChoice
        objectName: "interfaceSize_" + root.key
        Layout.fillWidth: true
        theme: root.theme
        model: root.cursor ? ["Default · 24 px", "Large · 32 px", "Extra large · 48 px"] : ["Default · 100%", "Large · 115%", "Extra large · 130%"]
        currentIndex: root.ready ? root.values.indexOf(root.backend.saved[root.key]) : -1
        enabled: root.ready && root.backend.writable
        Accessible.name: root.cursor ? "Pointer size" : "Text size"
        onActivated: index => {
            if (index >= 0 && index < root.values.length) root.backend.apply(root.key, root.values[index], root.snapshot)
            currentIndex = Qt.binding(() => root.ready ? root.values.indexOf(root.backend.saved[root.key]) : -1)
        }
    }
    Connections {
        target: sizeChoice.popup
        function onAboutToShow() { root.snapshot = root.backend.snapshot() }
        function onClosed() { Qt.callLater(() => { if (!sizeChoice.popup.visible) root.snapshot = null }) }
    }
    Text {
        Layout.fillWidth: true
        text: root.cursor ? "Saved for the desktop and compatible applications. Theme changes keep this size. Some applications may need reopening."
            : "Shell text updates immediately. Compatible apps use the desktop text-size setting; some need reopening or have their own font controls. Display scaling is separate."
        color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        visible: root.ready && root.backend.desktop[root.key] !== root.backend.saved[root.key]
        text: root.ready ? "Desktop setting differs from the saved preference: " + (root.cursor ? root.backend.desktop[root.key] + " px" : Math.round(root.backend.desktop[root.key] * 100) + "%") + ". Choose a size to apply it again." : ""
        color: root.theme.warning; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        text: root.backend === null ? "Interface sizing unavailable." : root.backend.error || (!root.ready ? "Loading interface sizes…" : root.backend.message)
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
