pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../Settings"

ColumnLayout {
    id: root
    required property var theme
    required property var backend
    required property var owner
    readonly property var request: backend ? backend.prompt : null
    visible: request !== null && backend.actionOwner === owner
    spacing: 8
    onRequestChanged: code.text = ""
    Text {
        Layout.fillWidth: true
        text: root.backend ? "Pairing with " + root.backend.actionName : ""
        textFormat: Text.PlainText
        color: root.theme.text
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.textSize
        font.weight: Font.DemiBold
        wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        text: !root.request ? "" : root.request.type === "display"
            ? "Type " + root.request.code + " on the Bluetooth device, then press Enter."
            : root.request.type === "pin" ? "Enter the device’s pairing PIN."
            : root.request.type === "passkey" ? "Enter the device’s six-digit pairing code."
            : root.request.code ? "Does " + root.request.code + " match the code on your device?"
            : root.request.service ? "Allow the device’s requested Bluetooth service?" : "Allow this device to pair?"
        textFormat: Text.PlainText
        color: root.theme.text
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.smallTextSize
        wrapMode: Text.WordWrap
    }
    ControlTextField {
        id: code
        objectName: "bluetoothPairingCode"
        Layout.fillWidth: true
        visible: root.request !== null && ["pin", "passkey"].includes(root.request.type)
        theme: root.theme
        secret: true
        maximumLength: root.request && root.request.type === "passkey" ? 6 : 16
        Accessible.name: "Bluetooth pairing code"
        onAccepted: if (submit.enabled) { root.backend.respond(text); text = "" }
    }
    Flow {
        Layout.fillWidth: true
        spacing: 8
        SettingsButton {
            id: submit
            objectName: "bluetoothPairingConfirm"
            theme: root.theme
            visible: root.request !== null && root.request.type !== "display"
            text: root.request && root.request.type === "confirm" ? "Confirm" : "Submit code"
            enabled: root.request !== null && (root.request.type === "confirm"
                || (root.request.type === "passkey" ? /^[0-9]{1,6}$/.test(code.text) : /^[\x20-\x7e]{1,16}$/.test(code.text)))
            onClicked: { root.backend.respond(root.request.type === "confirm" ? true : code.text); code.text = "" }
        }
        SettingsButton {
            objectName: "bluetoothPairingReject"
            theme: root.theme
            text: "Cancel pairing"
            onClicked: { code.text = ""; root.backend.cancelPairing() }
        }
    }
}
