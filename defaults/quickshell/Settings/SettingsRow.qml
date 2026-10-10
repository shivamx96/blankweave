pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../Components"

Item {
    id: root
    required property var theme
    required property var setting
    property var backend: null
    readonly property bool live: Boolean(setting.live && backend)
    readonly property bool writable: live && backend.ready && !backend.busy
        && (typeof backend.canApply !== "function" || backend.canApply(setting.id))
        && (setting.kind !== "slider" || typeof backend.value === "function")
    readonly property real sliderValue: live && typeof backend.value === "function" ? backend.value(setting.id) : -1
    readonly property string description: live && typeof backend.description === "function"
        ? backend.description(setting.id) || setting.description : setting.description
    readonly property var choices: live ? backend.choices(setting.id) : (setting.options || [])
    readonly property int selection: live ? backend.selection(setting.id) : 0
    readonly property bool compact: width < 510
    implicitHeight: content.implicitHeight + 28

    GridLayout {
        id: content
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 18 }
        columns: root.compact ? 1 : 2
        rowSpacing: 12
        columnSpacing: 20

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 5
            Text {
                Layout.fillWidth: true
                text: root.setting.title
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.textSize
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                objectName: "settingsDescription_" + root.setting.id
                text: root.description + (root.live ? "" : "  ·  Preview")
                color: root.theme.textMuted
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.smallTextSize
                wrapMode: Text.WordWrap
            }
        }

        Loader {
            Layout.preferredWidth: root.compact ? Math.min(240, content.width) : 190
            Layout.preferredHeight: 36
            sourceComponent: root.setting.kind === "choice" ? choiceControl
                : root.setting.kind === "slider" ? sliderControl
                : root.setting.kind === "toggle" ? toggleControl : actionControl
        }
    }

    Component {
        id: choiceControl
        SettingsComboBox {
            id: choice
            theme: root.theme
            objectName: "settingsChoice_" + root.setting.id
            model: root.choices
            currentIndex: root.selection
            enabled: root.writable && root.choices.length > 0
            Accessible.name: root.setting.title
            Accessible.description: root.description
            onActivated: index => {
                root.backend.apply(root.setting.id, index)
                // Keep the displayed choice tied to confirmed configuration,
                // including when an asynchronous apply fails without a change.
                currentIndex = Qt.binding(() => root.selection)
            }
        }
    }
    Component {
        id: sliderControl
        RowLayout {
            spacing: 10
            ControlSlider {
                id: slider
                objectName: "settingsSlider_" + root.setting.id
                Layout.fillWidth: true
                theme: root.theme
                from: root.setting.minimum
                to: root.setting.maximum
                stepSize: 1
                value: Math.max(from, root.sliderValue)
                enabled: root.writable
                opacity: enabled ? 1 : 0.45
                Accessible.name: root.setting.title
                Accessible.description: root.description
                property bool dragging: false
                property var dragBackend: null
                onMoved: if (root.writable) root.backend.adjust(root.setting.id, value)
                onPressedChanged: {
                    if (pressed) {
                        dragging = true
                        dragBackend = root.backend
                        dragBackend.hold(root.setting.id, true)
                    } else if (dragging) {
                        dragging = false
                        if (root.writable && dragBackend === root.backend) dragBackend.apply(root.setting.id, value)
                        dragBackend.hold(root.setting.id, false)
                        dragBackend = null
                    }
                }
                Component.onDestruction: if (dragBackend) dragBackend.hold(root.setting.id, false)
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -3
                    color: "transparent"
                    radius: root.theme.widgetRadius
                    border.width: slider.activeFocus ? 1 : 0
                    border.color: root.theme.accentBright
                }
            }
            Text {
                Layout.preferredWidth: 38
                text: root.sliderValue >= 0 ? Math.round(root.sliderValue) + "%" : "—"
                color: root.writable ? root.theme.text : root.theme.textMuted
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.smallTextSize
                horizontalAlignment: Text.AlignRight
            }
        }
    }
    Component {
        id: toggleControl
        Switch {
            enabled: false
            checked: false
            text: "Preview"
            Accessible.name: root.setting.title + " (preview)"
            palette.windowText: root.theme.textMuted
            font.family: root.theme.fontFamily
        }
    }
    Component {
        id: actionControl
        SettingsButton {
            theme: root.theme
            text: root.setting.action || "Configure"
            enabled: false
            Accessible.name: root.setting.title + " (preview)"
        }
    }
}
