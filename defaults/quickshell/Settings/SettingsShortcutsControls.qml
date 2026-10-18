pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var theme
    required property var backend
    readonly property bool ready: backend !== null && backend.ready
    readonly property var rows: ready ? backend.rows.filter(r => (r.label + " " + r.group + " " + r.value).toLowerCase().includes(search.text.toLowerCase())) : []
    property string selectedId: "settings"
    readonly property var selected: ready ? backend.rows.find(r => r.id === selectedId) || null : null
    property var draft: null
    readonly property var modifierChoices: ["", "SUPER", "CTRL", "ALT", "SHIFT", "SUPER + SHIFT", "SUPER + CTRL", "SUPER + ALT", "CTRL + ALT", "CTRL + SHIFT", "ALT + SHIFT", "SUPER + CTRL + SHIFT", "SUPER + ALT + SHIFT", "SUPER + CTRL + ALT", "CTRL + ALT + SHIFT", "SUPER + CTRL + ALT + SHIFT"]
    property string modifiers: ""
    property string key: ""
    function begin() {
        if (!selected || !selected.available || !backend.writable) return
        draft = {id: selected.id, label: selected.label, revision: backend.revision, session: backend.session, fingerprint: backend.fingerprint}
        const parts = selected.value.split(" + ")
        key = parts.pop()
        modifiers = ["SUPER", "CTRL", "ALT", "SHIFT"].filter(m => parts.includes(m)).join(" + ")
    }
    function otherChord(row) {
        return ["SUPER", "CTRL", "ALT", "SHIFT"].filter((m, i) => row.modmask & [64, 4, 8, 1][i]).concat([row.key || "keycode " + row.keycode]).join(" + ")
    }
    spacing: 10
    Text {
        Layout.fillWidth: true
        text: "Change desktop key combinations while keeping their actions. Conflicts with reported desktop bindings are checked before saving; applications may also use the same keys."
        color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap
    }
    SettingsTextField {
        theme: root.theme
        id: search
        objectName: "shortcutSearch"
        Layout.fillWidth: true
        placeholderText: "Find a shortcut…"
        Accessible.name: "Find a desktop shortcut"
    }
    SettingsComboBox {
        id: actionChoice
        objectName: "shortcutAction"
        Layout.fillWidth: true
        theme: root.theme
        property var menuRows: []
        property bool choosing: false
        readonly property var choices: choosing ? menuRows : root.rows
        model: choices.map(r => r.group + " · " + r.label + " — " + r.value)
        currentIndex: choices.findIndex(r => r.id === root.selectedId)
        displayText: currentIndex < 0 ? "Select a shortcut (" + choices.length + " matches)" : currentText
        enabled: root.ready && !root.backend.busy && root.draft === null
        Accessible.name: "Desktop shortcut action"
        onActivated: index => {
            if (choices[index]) root.selectedId = choices[index].id
            currentIndex = Qt.binding(() => choices.findIndex(r => r.id === root.selectedId))
        }
    }
    Connections {
        target: actionChoice.popup
        function onAboutToShow() { actionChoice.menuRows = root.rows.slice(); actionChoice.choosing = true }
        function onClosed() { Qt.callLater(() => { if (!actionChoice.popup.visible) actionChoice.choosing = false }) }
    }
    Text {
        Layout.fillWidth: true
        text: root.selected ? root.selected.label + ": " + root.selected.value + "\nDefault: " + root.selected.default
            + (root.selected.available ? "" : "\nThis binding is missing, overridden, or conflicts with personal configuration. Resolve that configuration before editing here.") : "Select an action to view its shortcut."
        color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap
    }
    RowLayout {
        visible: root.draft === null
        SettingsButton {
            objectName: "shortcutEdit"
            theme: root.theme; text: "Edit shortcut"
            enabled: root.ready && root.backend.writable && root.selected !== null && root.selected.available
            onClicked: root.begin()
        }
        SettingsButton {
            objectName: "shortcutReset"
            theme: root.theme; text: "Reset"
            enabled: root.ready && root.backend.writable && root.selected !== null && root.selected.available && root.selected.overridden
            onClicked: root.backend.apply(root.selected.id, null, root.backend.revision, root.backend.session, root.backend.fingerprint)
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.draft !== null
        Text {
            text: root.draft ? "Editing: " + root.draft.label : ""
            color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
        }
        SettingsComboBox {
            objectName: "shortcutModifiers"
            Layout.fillWidth: true
            theme: root.theme
            model: root.modifierChoices.map(m => m || "No modifiers")
            currentIndex: root.modifierChoices.indexOf(root.modifiers)
            enabled: root.ready && !root.backend.busy
            Accessible.name: "Shortcut modifiers"
            onActivated: index => { root.modifiers = root.modifierChoices[index]; currentIndex = Qt.binding(() => root.modifierChoices.indexOf(root.modifiers)) }
        }
        SettingsComboBox {
            objectName: "shortcutKey"
            Layout.fillWidth: true
            theme: root.theme
            model: root.ready ? root.backend.keys : []
            currentIndex: root.ready ? root.backend.keys.findIndex(k => k.toLowerCase() === root.key.toLowerCase()) : -1
            enabled: root.ready && !root.backend.busy
            Accessible.name: "Shortcut key"
            onActivated: index => { root.key = root.backend.keys[index]; currentIndex = Qt.binding(() => root.backend.keys.findIndex(k => k.toLowerCase() === root.key.toLowerCase())) }
        }
        Text {
            text: (root.modifiers ? root.modifiers + " + " : "") + root.key
            color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize
        }
        RowLayout {
            SettingsButton {
                objectName: "shortcutSave"
                theme: root.theme; text: "Save shortcut"
                enabled: root.ready && root.backend.writable && root.draft !== null && root.key !== ""
                onClicked: root.backend.apply(root.draft.id, (root.modifiers ? root.modifiers + " + " : "") + root.key,
                    root.draft.revision, root.draft.session, root.draft.fingerprint)
            }
            SettingsButton {
                theme: root.theme; text: "Done / discard edits"
                enabled: root.backend !== null && !root.backend.busy
                onClicked: root.draft = null
            }
        }
    }
    Connections {
        target: root.backend
        function onRevisionChanged() { root.draft = null }
    }
    SettingsButton {
        id: otherToggle
        theme: root.theme
        property bool expanded: false
        text: expanded ? "Hide other bindings" : "Show personal and other bindings"
        enabled: root.ready
        onClicked: expanded = !expanded
    }
    Repeater {
        model: root.ready && otherToggle.expanded ? root.backend.other : []
        delegate: Text {
            required property var modelData
            Layout.fillWidth: true
            text: root.otherChord(modelData) + " — " + (modelData.description || "Personal binding")
                + (modelData.release ? " (release)" : "") + (modelData.submap ? " · submap: " + modelData.submap : "") + " · Read-only"
            textFormat: Text.PlainText
            color: root.theme.textMuted; font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap
        }
    }
    Text {
        Layout.fillWidth: true
        text: root.backend === null ? "Shortcut settings unavailable." : root.backend.error
            || (!root.ready ? "Loading shortcuts…" : root.backend.message || "Changes are saved and applied immediately. Reset restores this action’s default combination.")
        color: root.backend && root.backend.error ? root.theme.warning : root.theme.textMuted
        font.family: root.theme.fontFamily; font.pixelSize: root.theme.smallTextSize; wrapMode: Text.WordWrap
    }
    SettingsButton {
        theme: root.theme; text: "Refresh"
        enabled: root.backend !== null && !root.backend.busy
        onClicked: { root.draft = null; root.backend.refresh(true) }
    }
}
