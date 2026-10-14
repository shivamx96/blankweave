pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var theme
    required property var backend
    readonly property bool ready: backend !== null && backend.ready
    property var draft: []
    property var expected: ({})
    property string token: ""
    property string desktop: ""
    property string options: ""
    property bool editing: false
    readonly property var shortcuts: [
        {value: "", label: "None"}, {value: "grp:alt_shift_toggle", label: "Alt + Shift"},
        {value: "grp:win_space_toggle", label: "Super + Space"}, {value: "grp:ctrl_shift_toggle", label: "Ctrl + Shift"}]
    readonly property string groupOptions: options.split(",").filter(o => o.startsWith("grp:")).join(",")
    readonly property var shortcutChoices: shortcuts.some(r => r.value === groupOptions) ? shortcuts
        : shortcuts.concat([{value: groupOptions, label: "Custom (current)"}])
    function begin() {
        if (!ready || editing) return
        expected = Object.assign({}, backend.values)
        token = backend.revision
        desktop = backend.session
        const variants = expected.kb_variant.split(",")
        draft = expected.kb_layout.split(",").map((layout, i) => ({layout: layout, variant: variants[i] || ""}))
        options = expected.kb_options
        editing = true
    }
    function label(row) {
        const match = backend ? backend.catalog.find(r => r.layout === row.layout && r.variant === row.variant) : null
        return match ? match.label : row.layout + (row.variant ? " (" + row.variant + ")" : "")
    }
    function move(index) {
        const rows = draft.slice(); const previous = rows[index - 1]; rows[index - 1] = rows[index]; rows[index] = previous; draft = rows
    }
    spacing: 10
    Text {
        Layout.fillWidth: true
        text: "Keyboard defaults apply to connected keyboards unless personally overridden. The first layout is the startup default. Input methods are configured separately."
        color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    property var selectedKeyboard: null
    readonly property var currentKeyboard: !ready ? null : selectedKeyboard === null
        ? backend.devices.find(d => d.main) || backend.devices[0] || null
        : backend.devices.find(d => d.name === selectedKeyboard.name && d.address === selectedKeyboard.address) || null
    SettingsComboBox {
        id: keyboardChoice
        Layout.fillWidth: true
        theme: root.theme
        property var menuDevices: []
        property bool choosing: false
        readonly property var devices: choosing ? menuDevices : root.ready ? root.backend.devices : []
        model: devices.map(d => d.name + (d.main ? " (main)" : ""))
        currentIndex: root.currentKeyboard ? devices.findIndex(d => d.address === root.currentKeyboard.address && d.name === root.currentKeyboard.name) : -1
        displayText: currentIndex < 0 ? "Select a connected keyboard" : currentText
        enabled: root.ready && !root.backend.busy
        Accessible.name: "Keyboard to switch"
        onActivated: index => {
            if (devices[index]) root.selectedKeyboard = Object.assign({}, devices[index])
            currentIndex = Qt.binding(() => root.currentKeyboard ? devices.findIndex(d => d.address === root.currentKeyboard.address && d.name === root.currentKeyboard.name) : -1)
        }
    }
    Connections {
        target: keyboardChoice.popup
        function onAboutToShow() { keyboardChoice.menuDevices = root.backend.devices.slice(); keyboardChoice.choosing = true }
        function onClosed() { Qt.callLater(() => { if (!keyboardChoice.popup.visible) keyboardChoice.choosing = false }) }
    }
    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: root.currentKeyboard ? "Current layout: " + root.currentKeyboard.active_keymap : "No keyboard selected."
            color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
            wrapMode: Text.WordWrap
        }
        SettingsButton {
            objectName: "keyboardNext"
            theme: root.theme; text: "Next layout"
            enabled: root.currentKeyboard !== null && !root.backend.busy && root.currentKeyboard.layout.split(",").length > 1
            onClicked: root.backend.switchLayout(Object.assign({}, root.currentKeyboard),
                (root.currentKeyboard.active_layout_index + 1) % root.currentKeyboard.layout.split(",").length)
        }
    }
    SettingsButton {
        objectName: "keyboardEdit"
        theme: root.theme; text: "Edit layouts"
        visible: !root.editing
        enabled: root.ready && root.backend.writable
        onClicked: root.begin()
    }
    ColumnLayout {
        visible: root.editing
        Layout.fillWidth: true
        Repeater {
            model: root.draft
            delegate: RowLayout {
                id: layoutRow
                required property var modelData
                required property int index
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: (layoutRow.index + 1) + ". " + root.label(layoutRow.modelData)
                    color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
                    wrapMode: Text.WordWrap
                }
                SettingsButton {
                    theme: root.theme; text: "↑"; enabled: layoutRow.index > 0 && !root.backend.busy
                    Accessible.name: "Move " + root.label(layoutRow.modelData) + " up"
                    onClicked: root.move(layoutRow.index)
                }
                SettingsButton {
                    theme: root.theme; text: "Remove"; enabled: root.draft.length > 1 && !root.backend.busy
                    Accessible.name: "Remove " + root.label(layoutRow.modelData)
                    onClicked: root.draft = root.draft.filter((r, i) => i !== layoutRow.index)
                }
            }
        }
        SettingsComboBox {
            id: addChoice
            objectName: "keyboardAdd"
            Layout.fillWidth: true
            theme: root.theme
            property var choices: []
            model: choices.map(r => r.label)
            currentIndex: -1; displayText: "Add layout or variant…"
            enabled: root.ready && !root.backend.busy && root.draft.length < 4
            Accessible.name: "Add keyboard layout or variant"
            onActivated: index => {
                const row = choices[index]
                if (row && root.draft.length < 4 && !root.draft.some(r => r.layout === row.layout && r.variant === row.variant))
                    root.draft = root.draft.concat([{layout: row.layout, variant: row.variant}])
                currentIndex = -1
            }
        }
        Connections {
            target: addChoice.popup
            function onAboutToShow() { addChoice.choices = root.backend.catalog.filter(r => !root.draft.some(d => r.layout === d.layout && r.variant === d.variant)) }
        }
        Text {
            text: "Layout switching shortcut"
            color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
        }
        SettingsComboBox {
            objectName: "keyboardShortcut"
            Layout.fillWidth: true
            theme: root.theme
            model: root.shortcutChoices.map(r => r.label)
            currentIndex: root.shortcutChoices.findIndex(r => r.value === root.groupOptions)
            enabled: root.ready && !root.backend.busy
            Accessible.name: "Layout switching shortcut"
            onActivated: index => {
                const row = root.shortcutChoices[index]
                if (row) root.options = root.options.split(",").filter(o => o && !o.startsWith("grp:")).concat(row.value ? [row.value] : []).join(",")
                currentIndex = Qt.binding(() => root.shortcutChoices.findIndex(r => r.value === root.groupOptions))
            }
        }
        RowLayout {
            SettingsButton {
                objectName: "keyboardSave"
                theme: root.theme; text: "Save layouts"
                enabled: root.ready && root.backend.writable
                onClicked: { root.backend.apply(root.draft, root.options, root.expected, root.token, root.desktop); root.editing = false }
            }
            SettingsButton {
                theme: root.theme; text: "Done / discard edits"
                enabled: root.backend !== null && !root.backend.busy
                onClicked: root.editing = false
            }
        }
    }
    Text {
        Layout.fillWidth: true
        text: root.backend === null ? "Keyboard settings unavailable." : root.backend.error
            || (!root.ready ? "Loading keyboard settings…" : root.backend.message
                || (root.backend.values.kb_file || !["", "evdev", "base"].includes(root.backend.values.kb_rules)
                    ? "A custom keymap or rules file is active. Edit it in your personal configuration."
                    : "Save applies the layout list immediately. Shortcuts may conflict with personal bindings."))
        color: root.backend && root.backend.error ? root.theme.warning : root.theme.textMuted
        font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap
    }
    RowLayout {
        SettingsButton {
            theme: root.theme; text: "Refresh"; enabled: root.backend !== null && !root.backend.busy
            onClicked: { root.editing = false; root.backend.refresh(true) }
        }
        SettingsButton {
            objectName: "keyboardReset"
            theme: root.theme; text: "Reset defaults"
            enabled: root.ready && root.backend.writable && Object.keys(root.backend.saved.values).length > 0
            onClicked: { root.editing = false; root.backend.apply(null, "", root.backend.values, root.backend.revision, root.backend.session) }
        }
    }
}
