pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var theme
    required property var backend
    readonly property bool ready: backend !== null && backend.ready
    readonly property var targets: [{scope: "global", label: "Pointer defaults"}, {scope: "touchpad", label: "Touchpad defaults"}]
        .concat(ready ? backend.devices.map(d => Object.assign({}, d, {scope: "device", label: d.name + (d.unique ? "" : " (ambiguous)")})) : [])
    property var target: ({scope: "global", label: "Pointer defaults"})
    property var menuTargets: []
    property bool selecting: false
    readonly property var targetChoices: selecting ? menuTargets : targets
    readonly property bool devicePresent: target.scope !== "device" || (ready && backend.devices.some(d => d.name === target.name && d.address === target.address))
    readonly property bool writable: ready && backend.writable(target)
    function sameTarget(a, b) { return a.scope === b.scope && a.name === b.name && a.address === b.address }
    function label(key) {
        return {sensitivity: "Pointer speed", accel_profile: "Acceleration", natural_scroll: "Natural scrolling",
            left_handed: "Left-handed buttons", tap_to_click: "Tap to click", disable_while_typing: "Disable touchpad while typing"}[key]
    }
    spacing: 12

    SettingsComboBox {
        id: deviceChoice
        objectName: "pointerTarget"
        Layout.fillWidth: true
        theme: root.theme
        model: root.targetChoices.map(row => row.label)
        currentIndex: root.targetChoices.findIndex(row => root.sameTarget(row, root.target))
        displayText: root.devicePresent ? currentText : "Device disconnected — select another"
        enabled: root.ready && !root.backend.busy
        Accessible.name: "Pointer settings target"
        onActivated: index => {
            const row = root.targetChoices[index]
            if (row) root.target = Object.assign({}, row)
            currentIndex = Qt.binding(() => root.targetChoices.findIndex(row => root.sameTarget(row, root.target)))
        }
    }
    Connections {
        target: deviceChoice.popup
        function onAboutToShow() { root.menuTargets = root.targets.slice(); root.selecting = true }
        function onClosed() { Qt.callLater(() => { if (!deviceChoice.popup.visible) root.selecting = false }) }
    }
    Text {
        Layout.fillWidth: true
        text: root.target.scope === "device"
            ? "These are saved overrides for this device name. Hyprland does not report every device’s effective value; personal overrides may take precedence. Reconnecting restores saved choices."
            : root.target.scope === "global"
            ? "Live pointer defaults. Speed and acceleration apply to mice and touchpads unless overridden per device."
            : "Live touchpad defaults. Individual device overrides take precedence."
        color: root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    Repeater {
        model: root.backend ? root.backend.fields(root.target) : []
        delegate: GridLayout {
            id: optionRow
            required property string modelData
            readonly property var choices: root.backend.choices(root.target, modelData)
            readonly property int selected: choices.findIndex(row => row.value === root.backend.value(root.target, modelData))
            // Freeze the identity and options at popup open; a hotplug or refresh
            // must not reinterpret an already-open menu's index.
            property var menuChoices: []
            property var menuTarget: null
            property bool choosing: false
            readonly property var visibleChoices: choosing ? menuChoices : choices
            Layout.fillWidth: true
            columns: root.width < 480 ? 1 : 3
            Text {
                Layout.fillWidth: true
                text: root.label(optionRow.modelData)
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.smallTextSize
                wrapMode: Text.WordWrap
            }
            SettingsComboBox {
                id: optionChoice
                objectName: "pointer_" + optionRow.modelData
                Layout.preferredWidth: root.width < 480 ? Math.min(240, root.width) : 175
                theme: root.theme
                model: optionRow.visibleChoices.map(row => row.label)
                currentIndex: optionRow.selected
                displayText: root.ready ? currentText : "Unavailable"
                enabled: root.writable
                Accessible.name: root.label(optionRow.modelData)
                onActivated: index => {
                    const choice = optionRow.visibleChoices[index]
                    if (choice) root.backend.apply(optionRow.choosing ? optionRow.menuTarget : root.target, optionRow.modelData, choice.value)
                    currentIndex = Qt.binding(() => optionRow.selected)
                }
            }
            Connections {
                target: optionChoice.popup
                function onAboutToShow() {
                    optionRow.menuChoices = optionRow.choices.slice()
                    optionRow.menuTarget = Object.assign({}, root.target)
                    optionRow.choosing = true
                }
                function onClosed() { Qt.callLater(() => { if (!optionChoice.popup.visible) optionRow.choosing = false }) }
            }
            SettingsButton {
                objectName: "pointerReset_" + optionRow.modelData
                theme: root.theme
                text: "Reset"
                enabled: root.writable && root.backend.overridden(root.target, optionRow.modelData)
                Accessible.name: "Reset " + root.label(optionRow.modelData)
                onClicked: root.backend.apply(root.target, optionRow.modelData, null)
            }
        }
    }
    Text {
        objectName: "pointerStatus"
        Layout.fillWidth: true
        text: root.backend === null ? "Pointer settings unavailable." : root.backend.error
            || (!root.devicePresent ? "This device disconnected. Select it again after reconnecting."
                : !root.ready ? "Loading pointer settings…" : root.backend.message
                || (root.backend.devices.length ? "Changes are saved and applied immediately." : "No pointer devices connected. Defaults still apply when a device connects."))
        color: root.backend && root.backend.error ? root.theme.warning : root.theme.textMuted
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    SettingsButton {
        objectName: "pointerRefresh"
        theme: root.theme
        text: "Refresh"
        enabled: root.backend !== null && !root.backend.busy
        onClicked: root.backend.refresh(true)
    }
}
