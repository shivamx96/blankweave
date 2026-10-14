pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var theme
    required property var backend
    readonly property bool ready: backend !== null && backend.ready
    readonly property bool writable: ready && backend.managed && backend.running && !backend.busy
    function label(key) {
        return {dim: "Dim screen after", lock: "Lock automatically after", screen: "Turn off screen after", suspend: "Suspend after"}[key]
    }
    spacing: 12

    Repeater {
        model: root.ready && root.backend.battery ? ["ac", "battery"] : ["ac"]
        delegate: ColumnLayout {
            id: supplyRow
            required property string modelData
            Layout.fillWidth: true
            visible: !root.ready || root.backend.managed
            Text {
                text: supplyRow.modelData === "ac" ? "Plugged in" : "On battery"
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.textSize
                font.weight: Font.Medium
            }
            GridLayout {
                Layout.fillWidth: true
                columns: root.width < 440 ? 1 : 2
                Repeater {
                    model: ["dim", "lock", "screen", "suspend"]
                    delegate: ColumnLayout {
                        id: timeoutRow
                        required property string modelData
                        Layout.fillWidth: true
                        Text {
                            text: root.label(timeoutRow.modelData)
                            color: root.theme.textMuted
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.smallTextSize
                        }
                        SettingsComboBox {
                            id: choice
                            objectName: "idle_" + supplyRow.modelData + "_" + timeoutRow.modelData
                            Layout.fillWidth: true
                            theme: root.theme
                            model: root.backend ? root.backend.labels : []
                            readonly property int selectedIndex: root.ready ? root.backend.delays.indexOf(root.backend.settings[supplyRow.modelData][timeoutRow.modelData]) : -1
                            currentIndex: selectedIndex
                            displayText: root.ready ? currentText : "Unavailable"
                            enabled: root.writable
                            Accessible.name: (supplyRow.modelData === "ac" ? "Plugged in: " : "On battery: ") + root.label(timeoutRow.modelData)
                            onActivated: index => {
                                root.backend.apply(supplyRow.modelData, timeoutRow.modelData, root.backend.delays[index])
                                currentIndex = Qt.binding(() => choice.selectedIndex)
                            }
                        }
                    }
                }
            }
        }
    }
    Text {
        Layout.fillWidth: true
        visible: root.ready && root.backend.managed
        text: "Changes restart idle timers. Dimming and locking may happen earlier to precede screen-off or sleep. Never disables only that idle action; manual locking and lock-before-suspend remain available. Lid behavior is managed by the system."
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    Text {
        objectName: "idleStatus"
        Layout.fillWidth: true
        text: root.backend === null ? "Idle settings unavailable." : root.backend.error
            || (!root.ready ? "Loading idle settings…" : root.backend.message)
        color: root.backend && root.backend.error ? root.theme.warning : root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    SettingsButton {
        objectName: "idleRefresh"
        theme: root.theme
        text: "Refresh"
        enabled: root.backend !== null && !root.backend.busy
        onClicked: root.backend.refresh(true)
    }
}
