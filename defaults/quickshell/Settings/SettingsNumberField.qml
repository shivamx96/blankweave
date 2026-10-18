import QtQuick
import QtQuick.Layouts

// Keep the user's text intact: invalid input is explained by the form rather
// than silently clamped or replaced when focus leaves the field.
RowLayout {
    id: root
    required property var theme
    required property string value
    required property string label
    required property int minimum
    required property int maximum
    readonly property bool valid: /^[0-9]+$/.test(value) && Number.isSafeInteger(Number(value))
        && Number(value) >= minimum && Number(value) <= maximum
    signal edited(string value)
    spacing: 8
    function step(delta) {
        if (valid && Number(value) + delta >= minimum && Number(value) + delta <= maximum)
            edited(String(Number(value) + delta))
    }
    SettingsButton {
        objectName: "numberDecrease"
        theme: root.theme
        text: "−"
        Accessible.name: "Decrease " + root.label
        enabled: root.valid && Number(root.value) > root.minimum
        onClicked: root.step(-1)
    }
    SettingsTextField {
        objectName: "numberText"
        theme: root.theme
        Layout.fillWidth: true
        Layout.minimumWidth: 60
        text: root.value
        inputMethodHints: Qt.ImhDigitsOnly
        Accessible.name: root.label
        Accessible.description: "Whole number from " + root.minimum + " to " + root.maximum
        onTextEdited: root.edited(text)
        Keys.onUpPressed: root.step(1)
        Keys.onDownPressed: root.step(-1)
    }
    SettingsButton {
        objectName: "numberIncrease"
        theme: root.theme
        text: "+"
        Accessible.name: "Increase " + root.label
        enabled: root.valid && Number(root.value) < root.maximum
        onClicked: root.step(1)
    }
}
